import 'song.dart';

class Album {
  final String id;
  final String name;
  final SongSource source;
  final String? coverUri;

  const Album({
    required this.id,
    required this.name,
    required this.source,
    this.coverUri,
  });
}