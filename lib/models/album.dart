import 'song.dart';

class Album {
  final String id;
  final String name;
  final SongSource source;
  final String? coverUri;
  final String? artist;
  final int? year;
  final String? genre;

  const Album({
    required this.id,
    required this.name,
    required this.source,
    this.coverUri,
    this.artist,
    this.year,
    this.genre,
  });

  /// Línea de datos para mostrar: "Artista · año · género".
  String get details => [
        if (artist != null) artist!,
        if (year != null) '$year',
        if (genre != null) genre!,
      ].join(' · ');

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'source': source.name,
      'coverUri': coverUri,
      'artist': artist,
      'year': year,
      'genre': genre,
    };
  }

  factory Album.fromMap(Map<String, dynamic> map) {
    return Album(
      id: map['id'] as String,
      name: map['name'] as String,
      source: SongSource.values.byName(map['source'] as String),
      coverUri: map['coverUri'] as String?,
      artist: map['artist'] as String?,
      year: map['year'] as int?,
      genre: map['genre'] as String?,
    );
  }
} 