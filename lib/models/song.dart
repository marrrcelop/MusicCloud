enum SongSource { drive, local }

class Song {
  final String id;
  final String title;
  final String artist;
  final SongSource source;
  final String path;

  // Opcionales: pueden ser null (es decir, "aún no tenemos ese dato")
  final String? albumId;
  final String? coverUri;
  final Duration? duration;

  const Song({
    required this.id,
    required this.title,
    required this.source,
    required this.path,
    this.artist = 'Artista desconocido',
    this.albumId,
    this.coverUri,
    this.duration,
  });

  /// Crea una copia de la canción cambiando solo lo que indiques.
  Song copyWith({
    String? id,
    String? title,
    String? artist,
    SongSource? source,
    String? path,
    String? albumId,
    String? coverUri,
    Duration? duration,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      source: source ?? this.source,
      path: path ?? this.path,
      albumId: albumId ?? this.albumId,
      coverUri: coverUri ?? this.coverUri,
      duration: duration ?? this.duration,
    );
  }

  /// Convierte la canción a un mapa (para guardarla en una base de datos o enviarla a un backend).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'source': source.name,
      'path': path,
      'albumId': albumId,
      'coverUri': coverUri,
      'durationMs': duration?.inMilliseconds,
    };
  }

  /// Reconstruye una canción a partir de un mapa.
  factory Song.fromMap(Map<String, dynamic> map) {
    final ms = map['durationMs'] as int?;
    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String? ?? 'Artista desconocido',
      source: SongSource.values.byName(map['source'] as String),
      path: map['path'] as String,
      albumId: map['albumId'] as String?,
      coverUri: map['coverUri'] as String?,
      duration: ms == null ? null : Duration(milliseconds: ms),
    );
  }

  /// Dos canciones son "la misma" si tienen el mismo id.
  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}