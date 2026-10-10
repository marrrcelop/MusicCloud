import 'dart:async';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/library.dart';
import '../models/library_view.dart';
import '../models/song.dart';
import '../services/app_error.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/cover_cache.dart';
import '../services/library_repository.dart';
import '../services/library_view_controller.dart';
import '../services/permission_service.dart';
import '../services/player_service.dart';
import 'widgets/album_list.dart';
import 'widgets/player_bar.dart';
import 'widgets/song_list.dart';
import 'widgets/sort_filter_sheet.dart';
import 'album_screen.dart';
import 'settings_screen.dart';

enum _MenuAction { settings, notifications, signOut }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerService _player = PlayerService();
  final AuthService _auth = AuthService();
  final ConnectivityService _connectivity = ConnectivityService();
  final PermissionService _permissions = PermissionService();
  final LibraryViewController _view = LibraryViewController();
  final TextEditingController _searchController = TextEditingController();
  late final LibraryRepository _repo = LibraryRepository(
    auth: _auth,
    isOnline: () => _online,
  );

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Object>? _playerErrorSub;

  /// True mientras se inicia sesión (también al abrir la app).
  bool _signingIn = true;
  bool _online = true;
  bool _playbackFailed = false;
  bool _askedNotifications = false;
  bool _searching = false;

  /// Error de inicio de sesión (los de la biblioteca están en el repositorio).
  AppError? _authError;

  @override
  void initState() {
    super.initState();
    // La caché de portadas necesita saber cómo pedir el token.
    CoverCache.instance.getHeaders = _auth.getHeaders;
    _repo.addListener(_onModelChanged);
    _view.addListener(_onModelChanged);
    _startListening();
    _bootstrap();
  }

  @override
  void dispose() {
    _repo.removeListener(_onModelChanged);
    _view.removeListener(_onModelChanged);
    _repo.dispose();
    _view.dispose();
    _searchController.dispose();
    _connectionSub?.cancel();
    _playerErrorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  // ---------- Escuchas ----------

  Future<void> _startListening() async {
    _playerErrorSub = _player.errorStream.listen(_onPlayerError);
    final online = await _connectivity.checkOnline();
    if (!mounted) return;
    setState(() => _online = online);
    _connectionSub = _connectivity.onlineStream.listen(_onConnectivityChanged);
  }

  Future<void> _onConnectivityChanged(bool online) async {
    final wasOffline = !_online;
    if (!mounted) return;
    setState(() => _online = online);
    if (!online || !wasOffline) return;

    // Volvió el internet: damos un segundo para que la red se estabilice.
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final busy = _repo.loading || _signingIn;
    final needsLogin = (_repo.error ?? _authError)?.needsLogin ?? false;
    if (!busy && !_repo.upToDate && !needsLogin) {
      _retryLibrary();
    }
    if (_playbackFailed) {
      _retryPlayback();
    }
  }

  void _onPlayerError(Object error) {
    _playbackFailed = true;
    _showError(_toAppError(error).message, retry: true);
  }

  // ---------- Errores ----------

  /// Sin internet casi cualquier fallo es de conexión, así que lo decimos así.
  AppError _toAppError(Object e) =>
      _online ? AppError.from(e) : AppError.offline;

  void _showError(String message, {bool retry = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      action: retry
          ? SnackBarAction(label: 'Reintentar', onPressed: _retryPlayback)
          : null,
    ));
  }

  // ---------- Sesión ----------

  /// Al abrir: primero muestra lo guardado en el teléfono (al instante) y
  /// después inicia sesión y actualiza desde Drive por detrás.
  Future<void> _bootstrap() async {
    await _view.loadPrefs();
    await _repo.loadSaved();
    await _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    setState(() {
      _authError = null;
      _signingIn = true;
    });
    try {
      if (await _auth.trySilentSignIn()) {
        await _refresh(interactive: false);
      }
    } catch (e) {
      debugPrint('Auto-login falló: $e');
      if (!_online && mounted) setState(() => _authError = AppError.offline);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _authError = null;
      _signingIn = true;
    });
    try {
      await _auth.signIn();
      await _refresh(interactive: true);
    } catch (e) {
      debugPrint('Error de login: $e');
      if (mounted && !AuthService.isCancelled(e)) {
        setState(() => _authError = _toAppError(e));
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'Se detendrá la música y se cerrará tu sesión de Google. '
          'Tu música en Drive no se modifica.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _signOut();
  }

  Future<void> _signOut() async {
    await _player.close();
    await _repo.clear();
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión: $e');
    }
    if (!mounted) return;
    _searchController.clear();
    _view.clearAll();
    setState(() {
      _authError = null;
      _signingIn = false;
      _playbackFailed = false;
      _searching = false;
    });
  }

  // ---------- Biblioteca ----------

  /// Actualiza la biblioteca y avisa al usuario si hace falta.
  Future<void> _refresh({required bool interactive}) async {
    final result = await _repo.refresh(interactive: interactive);
    if (!mounted) return;

    if (result.status == RefreshStatus.incomplete) {
      _showError(
        'Algunas portadas o datos no se pudieron cargar. '
        'Toca actualizar para reintentar.',
      );
    } else if (result.status == RefreshStatus.failed && _repo.hasSongs) {
      // Si ya hay biblioteca a la vista, solo avisamos; no la tapamos.
      _showError(result.error!.message);
    }
  }

  Future<void> _retryLibrary() {
    return _auth.isSignedIn ? _refresh(interactive: false) : _tryAutoLogin();
  }

  // ---------- Búsqueda, orden y filtros ----------

  void _startSearch() => setState(() => _searching = true);

  void _stopSearch() {
    _searchController.clear();
    _view.setSearch('');
    setState(() => _searching = false);
  }

  void _clearSearchText() {
    _searchController.clear();
    _view.setSearch('');
  }

  void _clearSearchAndFilters() {
    _searchController.clear();
    _view.clearAll();
  }

  void _openSortFilter(Library library) {
    SortFilterSheet.show(
      context,
      controller: _view,
      options: _view.optionsOf(library),
    );
  }

  // ---------- Reproducción ----------

  /// Pide el permiso de notificaciones, una sola vez por sesión.
  Future<void> _askNotificationsOnce() async {
    if (_askedNotifications) return;
    _askedNotifications = true;
    try {
      await _permissions.requestNotifications();
    } catch (e) {
      debugPrint('No se pudo pedir el permiso de notificaciones: $e');
    }
  }

  /// Reproduce una lista de canciones empezando por la posición indicada.
  Future<void> _play(List<Song> queue, int index) async {
    if (queue[index].source == SongSource.drive && !_online) {
      _showError('Sin conexión. Las canciones de Drive necesitan internet.');
      return;
    }
    await _askNotificationsOnce();
    try {
      _playbackFailed = false;
      await _player.playQueue(queue, index, getDriveHeaders: _auth.getHeaders);
    } catch (e) {
      debugPrint('Error al reproducir: $e');
      _playbackFailed = true;
      _showError(_toAppError(e).message, retry: true);
    }
  }

  Future<void> _retryPlayback() async {
    try {
      await _player.retryCurrent();
      _playbackFailed = false;
    } catch (e) {
      debugPrint('Reintento fallido: $e');
      _showError(_toAppError(e).message, retry: true);
    }
  }

  // ---------- Navegación ----------

  void _openAlbum(LibraryView view, Album album) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AlbumScreen(
        album: album,
        songs: view.songsOf(album.id),
        player: _player,
        onPlay: _play,
      ),
    ));
  }

  void _onMenuSelected(_MenuAction action) {
    switch (action) {
      case _MenuAction.settings:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SettingsScreen(),
        ));
      case _MenuAction.notifications:
        _permissions.openSettings();
      case _MenuAction.signOut:
        _confirmSignOut();
    }
  }

  // ---------- Pantalla ----------

  @override
  Widget build(BuildContext context) {
    final busy = _repo.loading || _signingIn;
    final library = _repo.library;
    final view =
        (_repo.hasSongs && library != null) ? _view.viewOf(library) : null;

    return PopScope(
      // Con la búsqueda abierta, "atrás" la cierra en vez de salir de la app.
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSearch();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: _buildAppBar(busy, library, view),
          body: Column(
            children: [
              if (!_online) _buildOfflineBanner(),
              if (!_auth.isSignedIn && _repo.hasSongs && !busy)
                _buildSessionBanner(),
              if (_view.hasFilters) _buildActiveFilters(),
              Expanded(child: _buildContent(view)),
            ],
          ),
          bottomNavigationBar: PlayerBar(player: _player),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    bool busy,
    Library? library,
    LibraryView? view,
  ) {
    final tabs = view == null
        ? null
        : TabBar(
            tabs: [
              Tab(text: 'Canciones (${view.songs.length})'),
              Tab(text: 'Álbumes (${view.albums.length})'),
            ],
          );

    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Cerrar búsqueda',
          icon: const Icon(Icons.arrow_back),
          onPressed: _stopSearch,
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Buscar canción, artista o álbum',
            border: InputBorder.none,
          ),
          onChanged: _view.setSearch,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              tooltip: 'Borrar',
              icon: const Icon(Icons.close),
              onPressed: _clearSearchText,
            ),
        ],
        bottom: tabs,
      );
    }

    return AppBar(
      title: const Text('MusicCloud'),
      actions: [
        if (library != null && _repo.hasSongs) ...[
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: _startSearch,
          ),
          IconButton(
            tooltip: 'Ordenar y filtrar',
            icon: Badge(
              label: Text('${_view.filterCount}'),
              isLabelVisible: _view.hasFilters,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => _openSortFilter(library),
          ),
        ],
        if (_auth.isSignedIn)
          IconButton(
            tooltip: 'Actualizar biblioteca',
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : () => _refresh(interactive: true),
          ),
        _buildMenu(),
      ],
      bottom: tabs,
    );
  }

  Widget _buildMenu() {
    return PopupMenuButton<_MenuAction>(
      onSelected: _onMenuSelected,
      itemBuilder: (context) {
        final email = _auth.userEmail;
        return <PopupMenuEntry<_MenuAction>>[
          if (email != null)
            PopupMenuItem<_MenuAction>(enabled: false, child: Text(email)),
          const PopupMenuItem<_MenuAction>(
            value: _MenuAction.settings,
            child: Text('Personalización'),
          ),
          const PopupMenuItem<_MenuAction>(
            value: _MenuAction.notifications,
            child: Text('Ajustes de notificaciones'),
          ),
          if (_auth.isSignedIn)
            const PopupMenuItem<_MenuAction>(
              value: _MenuAction.signOut,
              child: Text('Cerrar sesión'),
            ),
        ];
      },
    );
  }

  Widget _buildOfflineBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Text('Sin conexión',
              style: TextStyle(color: scheme.onErrorContainer)),
        ],
      ),
    );
  }

  Widget _buildSessionBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sin sesión de Google: puedes ver tu biblioteca, pero no reproducir.',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(onPressed: _connect, child: const Text('Iniciar sesión')),
        ],
      ),
    );
  }

  /// Fila con los filtros activos; cada uno se quita con su X.
  Widget _buildActiveFilters() {
    Widget chip(String label, VoidCallback onDelete) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: InputChip(label: Text(label), onDeleted: onDelete),
          ),
        );

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (_view.artist != null)
            chip('Artista: ${_view.artist}', () => _view.setArtist(null)),
          if (_view.genre != null)
            chip('Género: ${_view.genre}', () => _view.setGenre(null)),
          if (_view.year != null)
            chip('Año: ${_view.year}', () => _view.setYear(null)),
        ],
      ),
    );
  }

  Widget _buildContent(LibraryView? view) {
    if (view != null) {
      if (view.songs.isEmpty) {
        return _buildMessage(
          icon: Icons.search_off,
          text: 'No hay canciones que coincidan con la búsqueda o los filtros.',
          buttonLabel: 'Quitar búsqueda y filtros',
          onPressed: _clearSearchAndFilters,
        );
      }
      return _buildLibrary(view);
    }

    if (_repo.loading || _signingIn) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _repo.error ?? _authError;
    if (error != null) {
      return _buildMessage(
        icon: _iconFor(error),
        text: error.message,
        detail: error.detail,
        buttonLabel: error.needsLogin ? 'Iniciar sesión de nuevo' : 'Reintentar',
        onPressed: () => error.needsLogin ? _connect() : _retryLibrary(),
      );
    }

    if (!_auth.isSignedIn) {
      return _buildMessage(
        icon: Icons.cloud_off,
        text: 'Conecta tu Google Drive para ver tu música',
        buttonLabel: 'Conectar con Google Drive',
        onPressed: _connect,
      );
    }

    return _buildMessage(
      icon: Icons.library_music,
      text: 'No se encontraron canciones en tu Drive',
      buttonLabel: 'Actualizar',
      onPressed: () => _refresh(interactive: false),
    );
  }

  Widget _buildLibrary(LibraryView view) {
    return Column(
      children: [
        if (_repo.loading || _signingIn) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Orden: ${_view.order.label} · '
              '${_view.ascending ? 'ascendente' : 'descendente'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              SongList(
                player: _player,
                songs: view.songs,
                onTap: (index) => _play(view.songs, index),
              ),
              AlbumList(
                albums: view.albums,
                countOf: (album) => view.songsOf(album.id).length,
                onTap: (album) => _openAlbum(view, album),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String text,
    required String buttonLabel,
    required VoidCallback onPressed,
    String? detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                detail,
                textAlign: TextAlign.center,
                maxLines: 6,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(AppError error) {
    switch (error.type) {
      case AppErrorType.noInternet:
        return Icons.wifi_off;
      case AppErrorType.sessionExpired:
        return Icons.lock_outline;
      case AppErrorType.driveBusy:
        return Icons.cloud_off;
      case AppErrorType.fileNotFound:
        return Icons.search_off;
      case AppErrorType.playback:
      case AppErrorType.unknown:
        return Icons.error_outline;
    }
  }
}