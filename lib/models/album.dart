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
}