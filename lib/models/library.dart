import 'album.dart';
import 'song.dart';

/// Clave para ordenar alfabéticamente sin que las tildes estorben
/// (así "Árbol" queda junto a la A y no después de la Z).
String sortKey(String text) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final buffer = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer.toString();
}

String songCountText(int count) => count == 1 ? '1 canción' : '$count canciones';

class Library {
  static const noAlbumId = '__no_album__';

  final List<Song> songs;
  final List<Album> albums;
  final Map<String, List<Song>> _songsByAlbum;

  /// True si faltaron portadas o datos porque Drive no respondió a tiempo.
  final bool incomplete;

  Library._(this.songs, this.albums, this._songsByAlbum, this.incomplete);

  /// Arma la biblioteca a partir de las canciones y los álbumes (carpetas).
  factory Library.build({
    required List<Song> songs,
    required Map<String, Album> folders,
    bool incomplete = false,
  }) {
    final sorted = [...songs]
      ..sort((a, b) => sortKey(a.title).compareTo(sortKey(b.title)));

    final byAlbum = <String, List<Song>>{};
    for (final song in sorted) {
      final parent = song.albumId;
      final key =
          (parent != null && folders.containsKey(parent)) ? parent : noAlbumId;
      byAlbum.putIfAbsent(key, () => []).add(song);
    }

    // Dentro de un álbum, las pistas siguen el nombre del archivo (01, 02...).
    for (final list in byAlbum.values) {
      list.sort((a, b) => sortKey(a.fileName ?? a.title)
          .compareTo(sortKey(b.fileName ?? b.title)));
    }

    final albums = <Album>[
      for (final entry in byAlbum.entries)
        if (entry.key != noAlbumId) folders[entry.key]!,
    ]..sort((a, b) => sortKey(a.name).compareTo(sortKey(b.name)));

    if (byAlbum.containsKey(noAlbumId)) {
      albums.add(const Album(
        id: noAlbumId,
        name: 'Sin álbum',
        source: SongSource.drive,
      ));
    }

    return Library._(sorted, albums, byAlbum, incomplete);
  }

  /// Convierte la biblioteca a un mapa (para guardarla en el teléfono).
  Map<String, dynamic> toMap() {
    return {
      'songs': [for (final s in songs) s.toMap()],
      'albums': [
        for (final a in albums)
          if (a.id != noAlbumId) a.toMap(),
      ],
    };
  }

  /// Reconstruye la biblioteca guardada con [toMap].
  factory Library.fromMap(Map<String, dynamic> map) {
    final songs = [
      for (final m in (map['songs'] as List))
        Song.fromMap(m as Map<String, dynamic>),
    ];
    final albums = [
      for (final m in (map['albums'] as List))
        Album.fromMap(m as Map<String, dynamic>),
    ];
    return Library.build(
      songs: songs,
      folders: {for (final a in albums) a.id: a},
    );
  }

  List<Song> songsOf(String albumId) => _songsByAlbum[albumId] ?? const [];
}