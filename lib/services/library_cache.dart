import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/library.dart';

/// Un album.json ya descargado. Se guarda su texto y su fecha de modificación,
/// así solo se vuelve a descargar si cambió en Drive.
class CachedMeta {
  final String parent; // carpeta (álbum) a la que pertenece
  final String modified; // fecha de modificación en Drive
  final String text; // contenido del album.json

  const CachedMeta({
    required this.parent,
    required this.modified,
    required this.text,
  });

  Map<String, dynamic> toMap() =>
      {'parent': parent, 'modified': modified, 'text': text};

  factory CachedMeta.fromMap(Map<String, dynamic> map) => CachedMeta(
        parent: map['parent'] as String,
        modified: map['modified'] as String,
        text: map['text'] as String,
      );
}

class CachedLibrary {
  final Library library;
  final Map<String, CachedMeta> metas; // por id del archivo album.json

  const CachedLibrary(this.library, this.metas);
}

/// Guarda la biblioteca en el teléfono para abrir la app al instante
/// y poder verla aunque no haya internet.
class LibraryCache {
  static const _version = 1;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}library_cache.json');
  }

  Future<CachedLibrary?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;

      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['version'] != _version) return null;

      final library = Library.fromMap(data['library'] as Map<String, dynamic>);
      final rawMetas = data['metas'] as Map<String, dynamic>;
      final metas = {
        for (final e in rawMetas.entries)
          e.key: CachedMeta.fromMap(e.value as Map<String, dynamic>),
      };
      return CachedLibrary(library, metas);
    } catch (e) {
      // Una caché dañada no debe romper la app: simplemente se ignora.
      debugPrint('No se pudo leer la caché de la biblioteca: $e');
      return null;
    }
  }

  Future<void> save(Library library, Map<String, CachedMeta> metas) async {
    try {
      final file = await _file();
      final data = {
        'version': _version,
        'savedAt': DateTime.now().toIso8601String(),
        'library': library.toMap(),
        'metas': {for (final e in metas.entries) e.key: e.value.toMap()},
      };
      // Se escribe en un archivo temporal y luego se renombra, para no dejar
      // la caché a medias si la app se cierra justo mientras guarda.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(data), flush: true);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('No se pudo guardar la caché de la biblioteca: $e');
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Si no se puede borrar, no pasa nada.
    }
  }
}