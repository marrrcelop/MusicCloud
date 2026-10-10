import 'album.dart';
import 'library.dart';
import 'song.dart';

enum SortOrder {
  title('Título'),
  album('Álbum'),
  artist('Artista'),
  year('Año'),
  genre('Género'),
  added('Añadidas recientemente');

  final String label;
  const SortOrder(this.label);

  /// "Añadidas recientemente" empieza por lo más nuevo; el resto, de menor a mayor.
  bool get defaultAscending => this != SortOrder.added;

  static SortOrder fromName(String? name) => values.firstWhere(
        (o) => o.name == name,
        orElse: () => SortOrder.title,
      );
}

/// Valores disponibles para filtrar, sacados de toda la biblioteca.
class FilterOptions {
  final List<String> artists;
  final List<String> genres;
  final List<int> years;

  const FilterOptions(this.artists, this.genres, this.years);

  bool get isEmpty => artists.isEmpty && genres.isEmpty && years.isEmpty;

  factory FilterOptions.of(Library library) {
    // La clave normalizada evita duplicados como "Rock" y "rock".
    final artists = <String, String>{};
    final genres = <String, String>{};
    final years = <int>{};

    for (final s in library.songs) {
      if (s.artist != Song.unknownArtist) {
        artists.putIfAbsent(sortKey(s.artist), () => s.artist);
      }
      final genre = s.genre;
      if (genre != null) genres.putIfAbsent(sortKey(genre), () => genre);
      final year = s.year;
      if (year != null) years.add(year);
    }

    List<String> sortedValues(Map<String, String> map) =>
        (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => e.value)
            .toList();

    return FilterOptions(
      sortedValues(artists),
      sortedValues(genres),
      years.toList()..sort((a, b) => b.compareTo(a)), // años recientes primero
    );
  }
}

/// El resultado de aplicar búsqueda, filtros y orden a la biblioteca.
class LibraryView {
  /// Canciones que cumplen, ya ordenadas.
  final List<Song> songs;

  /// Álbumes con alguna canción que cumple, ya ordenados.
  final List<Album> albums;

  final Map<String, List<Song>> _byAlbum;

  LibraryView._(this.songs, this.albums, this._byAlbum);

  /// Canciones de un álbum que cumplen la búsqueda y los filtros.
  List<Song> songsOf(String albumId) => _byAlbum[albumId] ?? const [];

  factory LibraryView.build(
    Library library, {
    String search = '',
    String? artist,
    String? genre,
    int? year,
    required SortOrder order,
    required bool ascending,
  }) {
    final keys = _keysOf(library);
    final words =
        sortKey(search.trim()).split(' ').where((w) => w.isNotEmpty).toList();
    final artistKey = artist == null ? null : sortKey(artist);
    final genreKey = genre == null ? null : sortKey(genre);

    bool matches(Song s) {
      final k = keys[s.id]!;
      if (artistKey != null && k.artist != artistKey) return false;
      if (genreKey != null && k.genre != genreKey) return false;
      if (year != null && s.year != year) return false;
      if (words.isEmpty) return true;
      return words.every(k.haystack.contains);
    }

    // 1) Filtrar
    final songs = library.songs.where(matches).toList();
    final byAlbum = <String, List<Song>>{};
    for (final album in library.albums) {
      final list = library.songsOf(album.id).where(matches).toList();
      if (list.isNotEmpty) byAlbum[album.id] = list;
    }

    // 2) Ordenar canciones
    int tieBreak(Song a, Song b) {
      final ka = keys[a.id]!, kb = keys[b.id]!;
      var c = _cmpText(ka.album, kb.album, true);
      if (c != 0) return c;
      c = ka.file.compareTo(kb.file);
      if (c != 0) return c;
      return ka.title.compareTo(kb.title);
    }

    int compareSongs(Song a, Song b) {
      final ka = keys[a.id]!, kb = keys[b.id]!;
      final c = switch (order) {
        SortOrder.title => ascending
            ? ka.title.compareTo(kb.title)
            : kb.title.compareTo(ka.title),
        SortOrder.album => _cmpText(ka.album, kb.album, ascending),
        SortOrder.artist => _cmpText(ka.artist, kb.artist, ascending),
        SortOrder.year => _cmpNum(a.year, b.year, ascending),
        SortOrder.genre => _cmpText(ka.genre, kb.genre, ascending),
        SortOrder.added => _cmpNum(
            a.added?.millisecondsSinceEpoch,
            b.added?.millisecondsSinceEpoch,
            ascending,
          ),
      };
      return c != 0 ? c : tieBreak(a, b);
    }

    songs.sort(compareSongs);

    // 3) Ordenar álbumes
    final albumKeys = <String, _AlbumKeys>{
      for (final album in library.albums)
        if (byAlbum.containsKey(album.id))
          album.id: _albumKeysOf(album, byAlbum[album.id]!, keys),
    };

    int compareAlbums(Album a, Album b) {
      // "Sin álbum" siempre al final.
      if (a.id == Library.noAlbumId) {
        return b.id == Library.noAlbumId ? 0 : 1;
      }
      if (b.id == Library.noAlbumId) return -1;

      final ka = albumKeys[a.id]!, kb = albumKeys[b.id]!;
      final c = switch (order) {
        SortOrder.title || SortOrder.album => ascending
            ? ka.name.compareTo(kb.name)
            : kb.name.compareTo(ka.name),
        SortOrder.artist => _cmpText(ka.artist, kb.artist, ascending),
        SortOrder.year => _cmpNum(ka.year, kb.year, ascending),
        SortOrder.genre => _cmpText(ka.genre, kb.genre, ascending),
        SortOrder.added => _cmpNum(ka.added, kb.added, ascending),
      };
      return c != 0 ? c : ka.name.compareTo(kb.name);
    }

    final albums = [
      for (final album in library.albums)
        if (byAlbum.containsKey(album.id)) album,
    ]..sort(compareAlbums);

    return LibraryView._(songs, albums, byAlbum);
  }

  // ---------- Claves de orden (se calculan una vez por biblioteca) ----------

  static Library? _cachedLibrary;
  static Map<String, _Keys> _cachedKeys = {};

  static Map<String, _Keys> _keysOf(Library library) {
    if (!identical(_cachedLibrary, library)) {
      _cachedKeys = {for (final s in library.songs) s.id: _Keys(s)};
      _cachedLibrary = library;
    }
    return _cachedKeys;
  }
}

/// Textos de una canción ya normalizados (sin tildes ni mayúsculas).
class _Keys {
  final String title;
  final String? album;
  final String? artist;
  final String? genre;
  final String file;
  final String haystack;

  _Keys(Song s)
      : title = sortKey(s.title),
        album = s.albumName == null ? null : sortKey(s.albumName!),
        artist = s.artist == Song.unknownArtist ? null : sortKey(s.artist),
        genre = s.genre == null ? null : sortKey(s.genre!),
        file = sortKey(s.fileName ?? s.title),
        haystack = sortKey('${s.title} ${s.artist} ${s.albumName ?? ''}');
}

class _AlbumKeys {
  final String name;
  final String? artist;
  final String? genre;
  final int? year;
  final int? added;

  const _AlbumKeys(this.name, this.artist, this.genre, this.year, this.added);
}

/// Datos de un álbum para ordenarlo. Si el álbum no tiene artista, año o género
/// propios, se toman de sus canciones.
_AlbumKeys _albumKeysOf(
  Album album,
  List<Song> songs,
  Map<String, _Keys> keys,
) {
  String? artist = album.artist == null ? null : sortKey(album.artist!);
  String? genre = album.genre == null ? null : sortKey(album.genre!);
  int? year = album.year;
  int? added;

  for (final s in songs) {
    final k = keys[s.id]!;
    artist ??= k.artist;
    genre ??= k.genre;

    final songYear = s.year;
    if (album.year == null && songYear != null) {
      if (year == null || songYear < year) year = songYear;
    }

    final ms = s.added?.millisecondsSinceEpoch;
    if (ms != null && (added == null || ms > added)) added = ms;
  }

  return _AlbumKeys(sortKey(album.name), artist, genre, year, added);
}

/// Compara textos; los que faltan (null) van siempre al final.
int _cmpText(String? a, String? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return ascending ? a.compareTo(b) : b.compareTo(a);
}

/// Compara números; los que faltan (null) van siempre al final.
int _cmpNum(num? a, num? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return ascending ? a.compareTo(b) : b.compareTo(a);
}