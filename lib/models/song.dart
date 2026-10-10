enum SongSource { drive, local }

class Song {
  static const unknownArtist = 'Artista desconocido';

  final String id;
  final String title;
  final String artist;
  final SongSource source;
  final String path;

  /// Nombre del archivo (sirve para ordenar las pistas de un álbum).
  final String? fileName;
  final String? albumId;
  final String? albumName;
  final String? coverUri;
  final Duration? duration;
  final String? genre;
  final int? year;

  /// Cuándo se subió el archivo a Drive.
  final DateTime? added;

  const Song({
    required this.id,
    required this.title,
    required this.source,
    required this.path,
    String? artist,
    this.fileName,
    this.albumId,
    this.albumName,
    this.coverUri,
    this.duration,
    this.genre,
    this.year,
    this.added,
  }) : artist = artist ?? unknownArtist;

  /// Línea de datos para mostrar bajo el título: "Álbum · año · género".
  String get details => [
        if (albumName != null) albumName!,
        if (year != null) '$year',
        if (genre != null) genre!,
      ].join(' · ');

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    SongSource? source,
    String? path,
    String? fileName,
    String? albumId,
    String? albumName,
    String? coverUri,
    Duration? duration,
    String? genre,
    int? year,
    DateTime? added,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      source: source ?? this.source,
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      coverUri: coverUri ?? this.coverUri,
      duration: duration ?? this.duration,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      added: added ?? this.added,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'source': source.name,
      'path': path,
      'fileName': fileName,
      'albumId': albumId,
      'albumName': albumName,
      'coverUri': coverUri,
      'durationMs': duration?.inMilliseconds,
      'genre': genre,
      'year': year,
      'addedMs': added?.millisecondsSinceEpoch,
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    final durationMs = map['durationMs'] as int?;
    final addedMs = map['addedMs'] as int?;
    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String?,
      source: SongSource.values.byName(map['source'] as String),
      path: map['path'] as String,
      fileName: map['fileName'] as String?,
      albumId: map['albumId'] as String?,
      albumName: map['albumName'] as String?,
      coverUri: map['coverUri'] as String?,
      duration:
          durationMs == null ? null : Duration(milliseconds: durationMs),
      genre: map['genre'] as String?,
      year: map['year'] as int?,
      added: addedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(addedMs),
    );
  }

  /// Dos canciones son "la misma" si tienen el mismo id.
  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;
}