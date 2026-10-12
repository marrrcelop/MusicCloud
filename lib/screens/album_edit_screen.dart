import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/album.dart';
import '../services/image_tools.dart';
import '../services/library_repository.dart';
import 'widgets/album_cover.dart';
import 'widgets/library_actions.dart';

class AlbumEditScreen extends StatefulWidget {
  final Album album;
  final LibraryRepository repo;
  final LibraryActions actions;

  const AlbumEditScreen({
    super.key,
    required this.album,
    required this.repo,
    required this.actions,
  });

  @override
  State<AlbumEditScreen> createState() => _AlbumEditScreenState();
}

class _AlbumEditScreenState extends State<AlbumEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.album.name);
  late final TextEditingController _artist =
      TextEditingController(text: widget.album.artist ?? '');
  late final TextEditingController _genre =
      TextEditingController(text: widget.album.genre ?? '');
  late final TextEditingController _year =
      TextEditingController(text: widget.album.year?.toString() ?? '');

  PreparedImage? _cover;
  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _artist.dispose();
    _genre.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      final path = picked?.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      final dot = path.lastIndexOf('.');
      final separator = path.lastIndexOf(Platform.pathSeparator);
      final ext = dot > separator ? path.substring(dot + 1) : 'jpg';

      final prepared = await prepareCover(bytes, ext);
      if (!mounted) return;
      setState(() => _cover = prepared);
    } catch (e) {
      debugPrint('Error al elegir la portada: $e');
      widget.actions.notify('No se pudo cargar la imagen');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _formError = 'El álbum necesita un nombre.');
      return;
    }

    int? year;
    final yearText = _year.text.trim();
    if (yearText.isNotEmpty) {
      year = int.tryParse(yearText);
      if (year == null || year < 1000 || year > 2100) {
        setState(() => _formError = 'El año debe ser un número de 4 cifras.');
        return;
      }
    }

    if (!widget.actions.requireOnline()) return;
    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      final result = await widget.repo.saveAlbum(
        widget.album,
        name: name,
        artist: _artist.text,
        genre: _genre.text,
        year: year,
        cover: _cover,
      );
      if (!mounted) return;
      widget.actions.notify(
        result.status == RefreshStatus.failed
            ? 'Cambios guardados, pero no se pudo actualizar la lista. Toca actualizar.'
            : 'Álbum actualizado',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Error al guardar el álbum: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      widget.actions.notify(widget.actions.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = _cover;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar álbum')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: cover == null
                ? AlbumCover(album: widget.album, size: 160)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.memory(
                      cover.bytes,
                      width: 160,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('Elegir portada'),
              onPressed: _saving ? null : _pickCover,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Si la imagen es muy grande, se reduce automáticamente.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del álbum',
              helperText: 'Cambia el nombre de la carpeta en Drive.',
            ),
          ),
          TextField(
            controller: _artist,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Artista'),
          ),
          TextField(
            controller: _genre,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Género'),
          ),
          TextField(
            controller: _year,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(labelText: 'Año', counterText: ''),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}