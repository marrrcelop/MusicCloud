import 'dart:convert';
import 'file_names.dart';

/// Modifica el texto de un album.json respetando todo lo demás.
class AlbumMetaEditor {
  /// [album]: campos del álbum (artist, genre, year). Un valor null o vacío
  /// borra el campo.
  /// [songFileName] y [song]: campos de una canción (title, artist, genre, year).
  ///
  /// Lanza FormatException si el texto actual está mal escrito: en ese caso es
  /// mejor no tocarlo.
  static String apply(
    String? currentText, {
    Map<String, Object?> album = const {},
    String? songFileName,
    Map<String, Object?> song = const {},
  }) {
    final root = _parse(currentText);
    _setFields(root, album);

    if (songFileName != null) {
      final rawSongs = root['songs'];
      final songs = rawSongs is Map<String, dynamic> ? rawSongs : <String, dynamic>{};

      // Si la canción ya tiene entrada (con o sin extensión), usamos esa misma.
      final wanted = _norm(songFileName);
      final key = songs.keys.firstWhere(
        (k) => _norm(k) == wanted,
        orElse: () => baseName(songFileName),
      );

      final rawEntry = songs[key];
      final entry = rawEntry is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawEntry)
          : <String, dynamic>{};
      _setFields(entry, song);

      if (entry.isEmpty) {
        songs.remove(key);
      } else {
        songs[key] = entry;
      }
      if (songs.isEmpty) {
        root.remove('songs');
      } else {
        root['songs'] = songs;
      }
    }

    return const JsonEncoder.withIndent('  ').convert(root);
  }

  static Map<String, dynamic> _parse(String? text) {
    if (text == null) return <String, dynamic>{};
    final clean = text.startsWith('\uFEFF') ? text.substring(1) : text;
    if (clean.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(clean);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('album.json debe ser un objeto { ... }');
    }
    return decoded;
  }

  static void _setFields(Map<String, dynamic> target, Map<String, Object?> fields) {
    fields.forEach((key, value) {
      final v = value is String ? value.trim() : value;
      if (v == null || (v is String && v.isEmpty)) {
        target.remove(key);
      } else {
        target[key] = v;
      }
    });
  }

  static String _norm(String name) => baseName(name).trim().toLowerCase();
}