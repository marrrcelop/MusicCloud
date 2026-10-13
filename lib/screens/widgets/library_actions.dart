import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import '../../models/song.dart';
import '../../services/app_error.dart';
import '../../services/library_repository.dart';
import '../../services/player_service.dart';
import '../../services/upload_tools.dart';
import 'album_cover.dart';
import 'song_list.dart';
import 'upload_dialog.dart';

class LibraryActions {
  final LibraryRepository repo;
  final PlayerService player;
  final bool Function() isOnline;
  final Future<bool> Function() onWifi;
  final void Function(String message) notify;

  const LibraryActions({
    required this.repo,
    required this.player,
    required this.isOnline,
    required this.onWifi,
    required this.notify,
  });

  Future<void> handleSong(BuildContext context, Song song, SongAction action) {
    switch (action) {
      case SongAction.edit:
        return editSong(context, song);
      case SongAction.move:
        return moveSong(context, song);
      case SongAction.trash:
        return trashSong(context, song);
    }
  }

  // ---------- Canciones ----------

  Future<void> editSong(BuildContext context, Song song) async {
    if (!requireOnline()) return;
    final edits = await showDialog<_SongEdits>(
      context: context,
      builder: (_) => _SongEditDialog(song: song),
    );
    if (edits == null || !context.mounted) return;

    await _run(
      context,
      () => repo.saveSong(
        song,
        title: edits.title,
        artist: edits.artist,
        genre: edits.genre,
        year: edits.year,
      ),
      done: 'Datos guardados',
    );
  }

  Future<void> moveSong(BuildContext context, Song song) async {
    if (!requireOnline()) return;
    final library = repo.library;
    if (library == null) return;

    final choice = await showModalBottomSheet<_MoveChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MovePicker(
        albums: [
          for (final a in library.albums)
            if (a.id != Library.noAlbumId && a.id != song.albumId) a,
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    Album? destination = choice.album;
    if (choice.createNew) {
      final name = await _askAlbumName(context);
      if (name == null || !context.mounted) return;
      destination = await _createAlbumNamed(context, name);
      if (!context.mounted) return;
    }

    final dest = destination;
    if (dest == null) return;

    // No permitimos dos archivos con el mismo nombre en un álbum.
    final wanted = song.fileName?.toLowerCase();
    final repeated = repo.library
            ?.songsOf(dest.id)
            .any((s) => s.fileName?.toLowerCase() == wanted) ??
        false;
    if (repeated) {
      notify('Ya hay una canción con ese nombre en «${dest.name}».');
      return;
    }

    await _run(
      context,
      () => repo.moveSong(song, dest),
      done: 'Canción movida a «${dest.name}»',
    );
  }

  Future<void> trashSong(BuildContext context, Song song) async {
    if (!requireOnline()) return;
    final ok = await _confirm(
      context,
      title: 'Mover a la papelera',
      message: '«${song.title}» se moverá a la papelera de tu Drive. '
          'Drive la conserva un tiempo y puedes recuperarla desde allí.',
      action: 'Mover',
    );
    if (!ok || !context.mounted) return;

    if (player.currentSong?.id == song.id) await player.close();
    if (!context.mounted) return;

    await _run(
      context,
      () => repo.trashSong(song),
      done: 'Canción movida a la papelera',
    );
  }

  // ---------- Álbumes ----------

  /// Pide un nombre y crea el álbum. Devuelve el álbum creado (o null).
  Future<Album?> createAlbum(BuildContext context) async {
    if (!requireOnline()) return null;
    final name = await _askAlbumName(context);
    if (name == null || !context.mounted) return null;
    return _createAlbumNamed(context, name);
  }

  Future<Album?> _createAlbumNamed(BuildContext context, String name) async {
    String? newId;
    final ok = await _run(
      context,
      () async {
        newId = await repo.createAlbum(name);
        return const RefreshResult(RefreshStatus.ok);
      },
      done: 'Álbum creado',
    );

    final id = newId;
    if (!ok || id == null) return null;
    for (final album in repo.library?.albums ?? const <Album>[]) {
      if (album.id == id) return album;
    }
    return null;
  }

  /// Devuelve true si el álbum se movió a la papelera.
  Future<bool> trashAlbum(BuildContext context, Album album) async {
    if (!requireOnline()) return false;
    final ok = await _confirm(
      context,
      title: 'Mover álbum a la papelera',
      message: 'La carpeta «${album.name}» se moverá a la papelera de tu Drive '
          'junto con todo lo que contiene (canciones, imágenes y datos). '
          'Drive la conserva un tiempo y puedes recuperarla desde allí.',
      action: 'Mover',
    );
    if (!ok || !context.mounted) return false;

    if (player.currentSong?.albumId == album.id) await player.close();
    if (!context.mounted) return false;

    return _run(
      context,
      () => repo.trashAlbum(album),
      done: 'Álbum movido a la papelera',
    );
  }

  /// Elige archivos de audio del teléfono y los sube al álbum.
  Future<void> addSongs(BuildContext context, Album album) async {
    if (!requireOnline()) return;

    var picked = <PlatformFile>[];
    try {
      picked = await FilePicker.pickFiles(type: FileType.audio);
    } catch (e) {
      debugPrint('Error al abrir el selector de archivos: $e');
      notify('No se pudo abrir el selector de archivos.');
      return;
    }
    if (picked.isEmpty || !context.mounted) return; // canceló

    // Preparamos cada archivo: comprobamos que no esté vacío y que sea audio.
    final items = <UploadItem>[];
    final invalid = <String>[];
    for (final file in picked) {
      final path = file.path;
      if (path == null) {
        invalid.add(file.name);
        continue;
      }
      final item = await buildUploadItem(path, file.name);
      if (item == null) {
        invalid.add(file.name);
      } else {
        items.add(item);
      }
    }
    if (items.isEmpty) {
      notify('Ningún archivo se pudo preparar (¿están vacíos o no son de audio?).');
      return;
    }
    if (!context.mounted) return;

    // Con datos móviles, avisamos cuánto se va a gastar.
    if (!await onWifi()) {
      if (!context.mounted) return;
      final total = items.fold<int>(0, (sum, item) => sum + item.size);
      final ok = await _confirm(
        context,
        title: 'Estás sin Wi‑Fi',
        message: 'Vas a subir ${items.length} '
            '${items.length == 1 ? 'archivo' : 'archivos'} '
            '(${formatBytes(total)}) con datos móviles. ¿Continuar?',
        action: 'Subir',
      );
      if (!ok || !context.mounted) return;
    }

    await showDialog<UploadReport>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UploadDialog(
        repo: repo,
        album: album,
        items: items,
        notPrepared: invalid,
      ),
    );
  }

  // ---------- Apoyo ----------

  bool requireOnline() {
    if (isOnline()) return true;
    notify('Sin conexión. Para editar, mover o subir hace falta internet.');
    return false;
  }

  /// Texto para el usuario según el tipo de error.
  String messageFor(Object e) {
    if (!isOnline()) return AppError.offline.message;
    if (e is FormatException) {
      return 'El archivo album.json de este álbum tiene un error de formato. '
          'Corrígelo en Drive y vuelve a intentarlo.';
    }
    if (e is DriveException && (e.statusCode == 401 || e.statusCode == 403)) {
      return 'Sin permiso para modificar tu Drive. Toca actualizar (⟳) y '
          'acepta el permiso de edición.';
    }
    return AppError.from(e).message;
  }

  Future<String?> _askAlbumName(BuildContext context) {
    final existing = <String>{
      for (final a in repo.library?.albums ?? const <Album>[])
        a.name.trim().toLowerCase(),
    };
    return showDialog<String>(
      context: context,
      builder: (_) => _AlbumNameDialog(existing: existing),
    );
  }

  /// Ejecuta una operación mostrando un indicador de progreso.
  Future<bool> _run(
    BuildContext context,
    Future<RefreshResult> Function() action, {
    required String done,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final result = await action();
      navigator.pop();

      var message = done;
      if (result.status == RefreshStatus.failed) {
        message += ', pero no se pudo actualizar la lista. Toca actualizar';
      }
      if (result.warnings.isNotEmpty) {
        message += '. Avisos: ${result.warnings.join(' ')}';
      }
      notify(message);
      return true;
    } catch (e) {
      debugPrint('Error al modificar Drive: $e');
      navigator.pop();
      notify(messageFor(e));
      return false;
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ---------- Ventanas ----------

class _SongEdits {
  final String title;
  final String artist;
  final String genre;
  final int? year;

  const _SongEdits(this.title, this.artist, this.genre, this.year);
}

class _SongEditDialog extends StatefulWidget {
  final Song song;

  const _SongEditDialog({required this.song});

  @override
  State<_SongEditDialog> createState() => _SongEditDialogState();
}

class _SongEditDialogState extends State<_SongEditDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.song.title);
  late final TextEditingController _artist = TextEditingController(
    text: widget.song.artist == Song.unknownArtist ? '' : widget.song.artist,
  );
  late final TextEditingController _genre =
      TextEditingController(text: widget.song.genre ?? '');
  late final TextEditingController _year =
      TextEditingController(text: widget.song.year?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _genre.dispose();
    _year.dispose();
    super.dispose();
  }

  void _submit() {
    final yearText = _year.text.trim();
    int? year;
    if (yearText.isNotEmpty) {
      year = int.tryParse(yearText);
      if (year == null || year < 1000 || year > 2100) {
        setState(() => _error = 'El año debe ser un número de 4 cifras.');
        return;
      }
    }
    Navigator.pop(
      context,
      _SongEdits(_title.text, _artist.text, _genre.text, year),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar datos'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            TextField(
              controller: _artist,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Artista'),
            ),
            TextField(
              controller: _genre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Género'),
            ),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Año',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Si vacías un campo, se usa el valor del álbum '
              '(o el nombre del archivo en el título).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

/// Lo que el usuario eligió al mover una canción.
class _MoveChoice {
  final Album? album;
  final bool createNew;

  const _MoveChoice.existing(this.album) : createNew = false;
  const _MoveChoice.create()
      : album = null,
        createNew = true;
}

class _MovePicker extends StatelessWidget {
  final List<Album> albums;

  const _MovePicker({required this.albums});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Mover a…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Nuevo álbum…'),
            onTap: () => Navigator.pop(context, const _MoveChoice.create()),
          ),
          for (final album in albums)
            ListTile(
              leading: AlbumCover(album: album, size: 40),
              title: Text(album.name),
              onTap: () => Navigator.pop(context, _MoveChoice.existing(album)),
            ),
        ],
      ),
    );
  }
}

class _AlbumNameDialog extends StatefulWidget {
  /// Nombres de álbumes que ya existen, en minúsculas.
  final Set<String> existing;

  const _AlbumNameDialog({required this.existing});

  @override
  State<_AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends State<_AlbumNameDialog> {
  final TextEditingController _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe un nombre.');
      return;
    }
    if (widget.existing.contains(name.toLowerCase())) {
      setState(() => _error = 'Ya existe un álbum con ese nombre.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo álbum'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nombre del álbum',
              helperText: 'Se crea una carpeta en la raíz de tu Drive.',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Crear')),
      ],
    );
  }
}