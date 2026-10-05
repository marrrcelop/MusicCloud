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

  Library._(this.songs, this.albums, this._songsByAlbum);

  /// Arma la biblioteca a partir de las canciones y los nombres de las carpetas.
  factory Library.build({
    required List<Song> songs,
    required Map<String, String> folderNames,
  }) {
    final sorted = [...songs]
      ..sort((a, b) => sortKey(a.title).compareTo(sortKey(b.title)));

    final byAlbum = <String, List<Song>>{};
    for (final song in sorted) {
      final parent = song.albumId;
      final key = (parent != null && folderNames.containsKey(parent))
          ? parent
          : noAlbumId;
      byAlbum.putIfAbsent(key, () => []).add(song);
    }

    final albums = <Album>[
      for (final entry in byAlbum.entries)
        if (entry.key != noAlbumId)
          Album(
            id: entry.key,
            name: folderNames[entry.key]!,
            source: SongSource.drive,
          ),
    ]..sort((a, b) => sortKey(a.name).compareTo(sortKey(b.name)));

    if (byAlbum.containsKey(noAlbumId)) {
      albums.add(const Album(
        id: noAlbumId,
        name: 'Sin álbum',
        source: SongSource.drive,
      ));
    }

    return Library._(sorted, albums, byAlbum);
  }

  List<Song> songsOf(String albumId) => _songsByAlbum[albumId] ?? const [];
}