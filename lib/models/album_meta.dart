import 'dart:convert';
import 'file_names.dart';

/// Datos de una canción escritos en album.json.
class SongMeta {
  final String? title;
  final String? artist;
  final String? genre;
  final int? year;

  const SongMeta({this.title, this.artist, this.genre, this.year});
}

/// Datos de un álbum escritos en album.json.
class AlbumMeta {
  final String? artist;
  final String? genre;
  final int? year;
  final Map<String, SongMeta> _songs;

  const AlbumMeta({
    this.artist,
    this.genre,
    this.year,
    Map<String, SongMeta> songs = const {},
  }) : _songs = songs;

  factory AlbumMeta.fromJsonString(String source) {
    // Algunos editores de Windows agregan una marca invisible al inicio.
    final text = source.startsWith('\uFEFF') ? source.substring(1) : source;
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('album.json debe ser un objeto { ... }');
    }

    final songs = <String, SongMeta>{};
    final rawSongs = decoded['songs'];
    if (rawSongs is Map<String, dynamic>) {
      rawSongs.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          songs[_key(key)] = SongMeta(
            title: _text(value['title']),
            artist: _text(value['artist']),
            genre: _text(value['genre']),
            year: _number(value['year']),
          );
        }
      });
    }

    return AlbumMeta(
      artist: _text(decoded['artist']),
      genre: _text(decoded['genre']),
      year: _number(decoded['year']),
      songs: songs,
    );
  }

  /// Busca los datos de una canción por el nombre de su archivo.
  SongMeta? songFor(String fileName) => _songs[_key(fileName)];

  // Comparamos sin extensión, sin mayúsculas y sin espacios en los bordes.
  static String _key(String name) => baseName(name).trim().toLowerCase();

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static int? _number(Object? value) =>
      value is int ? value : (value is String ? int.tryParse(value.trim()) : null);
}