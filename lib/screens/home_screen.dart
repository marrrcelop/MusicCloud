import 'dart:async';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/library.dart';
import '../models/song.dart';
import '../services/app_error.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/drive_service.dart';
import '../services/permission_service.dart';
import '../services/player_service.dart';
import 'widgets/album_list.dart';
import 'widgets/player_bar.dart';
import 'widgets/song_list.dart';
import 'album_screen.dart';
import 'widgets/mascot_overlay.dart';
import 'settings_screen.dart';
import '../services/cover_cache.dart';

enum _MenuAction { settings, notifications, signOut }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerService _player = PlayerService();
  final AuthService _auth = AuthService();
  final DriveService _drive = DriveService();
  final ConnectivityService _connectivity = ConnectivityService();
  final PermissionService _permissions = PermissionService();

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Object>? _playerErrorSub;

  Library? _library;
  bool _loading = true;
  bool _online = true;
  bool _playbackFailed = false;
  bool _askedNotifications = false;
  AppError? _error;

  bool get _hasSongs => _library?.songs.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    CoverCache.instance.getHeaders = _auth.getHeaders;
    _startListening();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _playerErrorSub?.cancel();
    _player.dispose();
    super.dispose();
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

    if (!_hasSongs && !_loading && _error?.needsLogin != true) {
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

  Future<void> _tryAutoLogin() async {
    _error = null;
    if (!_loading) setState(() => _loading = true);
    try {
      if (await _auth.trySilentSignIn()) {
        await _loadLibrary(interactive: false);
        return;
      }
    } catch (e) {
      debugPrint('Auto-login falló: $e');
      if (!_online && mounted) setState(() => _error = AppError.offline);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.signIn();
      await _loadLibrary(interactive: true);
    } catch (e) {
      debugPrint('Error de login: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!AuthService.isCancelled(e)) _error = _toAppError(e);
      });
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
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión: $e');
    }
    if (!mounted) return;
    setState(() {
      _library = null;
      _error = null;
      _loading = false;
      _playbackFailed = false;
    });
  }

  // ---------- Biblioteca y reproducción ----------

  Future<void> _loadLibrary({required bool interactive}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final headers = await _auth.getHeaders(interactive: interactive);
      if (headers == null) throw const SessionException();
      final library = await _drive.fetchLibrary(_auth.getHeaders);
      if (!mounted) return;
      setState(() => _library = library);
    } catch (e) {
      debugPrint('Error cargando la biblioteca: $e');
      if (!mounted) return;
      final error = _toAppError(e);
      if (!_hasSongs) {
        setState(() => _error = error);
      } else {
        _showError(error.message); // conservamos la biblioteca que ya teníamos
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _retryLibrary() {
    return _auth.isSignedIn
        ? _loadLibrary(interactive: false)
        : _tryAutoLogin();
  }

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

  void _openAlbum(Library library, Album album) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AlbumScreen(
        album: album,
        songs: library.songsOf(album.id),
        player: _player,
        onPlay: _play,
      ),
    ));
  }

  void _onMenuSelected(_MenuAction action) {
    switch (action) {
      case _MenuAction.notifications:
        _permissions.openSettings();
      case _MenuAction.signOut:
        _confirmSignOut();
      case _MenuAction.settings:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SettingsScreen(),
        ));
    }
  }

  // ---------- Pantalla ----------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MusicCloud'),
          actions: [
            if (_auth.isSignedIn)
              IconButton(
                tooltip: 'Actualizar biblioteca',
                icon: const Icon(Icons.refresh),
                onPressed:
                    _loading ? null : () => _loadLibrary(interactive: true),
              ),
            PopupMenuButton<_MenuAction>(
              onSelected: _onMenuSelected,
              itemBuilder: (context) {
                final email = _auth.userEmail;
                return <PopupMenuEntry<_MenuAction>>[
                  if (email != null)
                    PopupMenuItem<_MenuAction>(
                      enabled: false,
                      child: Text(email),
                    ),
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
            ),
          ],
          bottom: _hasSongs
              ? const TabBar(
                  tabs: [
                    Tab(text: 'Canciones'),
                    Tab(text: 'Álbumes'),
                  ],
                )
              : null,
        ),
        body: Column(
          children: [
            if (!_online) _buildOfflineBanner(),
            Expanded(child: _buildContent()),
          ],
        ),
        bottomNavigationBar: PlayerBar(player: _player),
        floatingActionButton: const MascotOverlay(),
      ),
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

  Widget _buildContent() {
    final library = _library;
    if (library != null && library.songs.isNotEmpty) {
      return _buildLibrary(library);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return _buildMessage(
        icon: _iconFor(error),
        text: error.message,
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
      onPressed: () => _loadLibrary(interactive: false),
    );
  }

  Widget _buildLibrary(Library library) {
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: TabBarView(
            children: [
              SongList(
                player: _player,
                songs: library.songs,
                onTap: (index) => _play(library.songs, index),
              ),
              AlbumList(
                albums: library.albums,
                countOf: (album) => library.songsOf(album.id).length,
                onTap: (album) => _openAlbum(library, album),
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