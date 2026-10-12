import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../models/song.dart';
import '../../services/app_error.dart';
import '../../services/library_repository.dart';
import '../../services/player_service.dart';
import 'song_list.dart';

class LibraryActions {
  final LibraryRepository repo;
  final PlayerService player;
  final bool Function() isOnline;
  final void Function(String message) notify;

  const LibraryActions({
    required this.repo,
    required this.player,
    required this.isOnline,
    required this.notify,
  });

  Future<void> handleSong(BuildContext context, Song song, SongAction action) {
    switch (action) {
      case SongAction.edit:
        return editSong(context, song);
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

  // ---------- Apoyo ----------

  bool requireOnline() {
    if (isOnline()) return true;
    notify('Sin conexión. Para editar o borrar hace falta internet.');
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
      notify(
        result.status == RefreshStatus.failed
            ? '$done, pero no se pudo actualizar la lista. Toca actualizar.'
            : done,
      );
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