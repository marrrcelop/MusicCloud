import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/album.dart';
import '../models/album_meta.dart';
import '../models/file_names.dart';
import '../models/library.dart';
import '../models/song.dart';
import 'app_error.dart';
import 'drive_audio_source.dart';

class DriveService {
  static const _timeout = Duration(seconds: 20);
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Cuántas carpetas se consultan en cada petición a Drive.
  static const _foldersPerQuery = 20;

  /// Cuántos album.json se descargan a la vez.
  static const _parallelDownloads = 8;

  /// Descarga la lista de canciones, carpetas, imágenes y datos, y arma la biblioteca.
  Future<Library> fetchLibrary(HeadersProvider getHeaders) async {
    final audioFiles = await _listFiles(
      getHeaders,
      query: "mimeType contains 'audio/' and trashed = false",
      fields: 'id, name, parents',
    );
    final folderFiles = await _listFiles(
      getHeaders,
      query: "mimeType = '$_folderMime' and trashed = false",
      fields: 'id, name',
    );
    final folderNames = {
      for (final f in folderFiles) f['id'] as String: f['name'] as String,
    };

    // Solo miramos imágenes y datos dentro de las carpetas que tienen música.
    final parentIds = <String>{
      for (final f in audioFiles)
        if (_parentOf(f) != null) _parentOf(f)!,
    };

    final found = await Future.wait([
      _listInParents(
        getHeaders,
        parentIds,
        condition: "mimeType contains 'image/'",
        fields: 'id, name, parents, modifiedTime',
      ),
      _listInParents(
        getHeaders,
        parentIds,
        condition: "name = 'album.json'",
        fields: 'id, parents',
      ),
    ]);
    final imageFiles = found[0];
    final metaFiles = found[1];

    final metaByParent = await _downloadMeta(getHeaders, metaFiles);

    // Índice de imágenes: portada del álbum y portada propia de cada canción.
    final albumCovers = <String, String>{}; // carpeta -> portada
    final songCovers = <String, String>{}; // "carpeta|nombre" -> portada
    for (final f in imageFiles) {
      final parent = _parentOf(f);
      if (parent == null) continue;
      final name = baseName(f['name'] as String).toLowerCase();
      final ref = _coverRef(f);
      if (name == 'cover') {
        albumCovers.putIfAbsent(parent, () => ref);
      } else {
        songCovers.putIfAbsent('$parent|$name', () => ref);
      }
    }

    // Álbumes (carpetas)
    final folders = <String, Album>{};
    for (final id in parentIds) {
      final name = folderNames[id];
      if (name == null) continue; // carpeta raíz u otra que no podemos nombrar
      final meta = metaByParent[id];
      folders[id] = Album(
        id: id,
        name: name,
        source: SongSource.drive,
        coverUri: albumCovers[id],
        artist: meta?.artist,
        year: meta?.year,
        genre: meta?.genre,
      );
    }

    // Canciones
    final songs = <Song>[];
    for (final f in audioFiles) {
      final id = f['id'] as String;
      final fileName = f['name'] as String;
      final parent = _parentOf(f);
      final album = parent == null ? null : folders[parent];
      final meta = parent == null ? null : metaByParent[parent];
      final songMeta = meta?.songFor(fileName);
      final ownCover = parent == null
          ? null
          : songCovers['$parent|${baseName(fileName).toLowerCase()}'];

      songs.add(Song(
        id: id,
        title: songMeta?.title ?? baseName(fileName),
        artist: songMeta?.artist ?? meta?.artist,
        source: SongSource.drive,
        path: id,
        fileName: fileName,
        albumId: parent,
        albumName: album?.name,
        coverUri: ownCover ?? album?.coverUri,
        genre: songMeta?.genre ?? meta?.genre,
        year: songMeta?.year ?? meta?.year,
      ));
    }

    return Library.build(songs: songs, folders: folders);
  }

  /// Descarga el contenido de un archivo de Drive (imágenes, album.json...).
  Future<Uint8List> downloadBytes(HeadersProvider getHeaders, String fileId) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
    });
    final response = await _get(getHeaders, uri);
    return response.bodyBytes;
  }

  // ---------- Datos de los álbumes (album.json) ----------

  Future<Map<String, AlbumMeta>> _downloadMeta(
    HeadersProvider getHeaders,
    List<Map<String, dynamic>> files,
  ) async {
    final result = <String, AlbumMeta>{};

    for (var i = 0; i < files.length; i += _parallelDownloads) {
      final batch = files.sublist(
        i,
        math.min(i + _parallelDownloads, files.length),
      );
      final parsed = await Future.wait(
        batch.map((f) => _downloadOneMeta(getHeaders, f)),
      );
      for (var j = 0; j < batch.length; j++) {
        final parent = _parentOf(batch[j]);
        final meta = parsed[j];
        if (parent != null && meta != null) {
          result.putIfAbsent(parent, () => meta);
        }
      }
    }
    return result;
  }

  Future<AlbumMeta?> _downloadOneMeta(
    HeadersProvider getHeaders,
    Map<String, dynamic> file,
  ) async {
    try {
      final bytes = await downloadBytes(getHeaders, file['id'] as String);
      return AlbumMeta.fromJsonString(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      // Un album.json mal escrito no debe romper toda la biblioteca.
      debugPrint('No se pudo leer album.json (${file['id']}): $e');
      return null;
    }
  }

  // ---------- Consultas a Drive ----------

  /// Busca archivos que cumplan una condición y estén en alguna de esas carpetas.
  Future<List<Map<String, dynamic>>> _listInParents(
    HeadersProvider getHeaders,
    Set<String> parentIds, {
    required String condition,
    required String fields,
  }) async {
    final ids = parentIds.toList();
    final queries = <Future<List<Map<String, dynamic>>>>[];

    for (var i = 0; i < ids.length; i += _foldersPerQuery) {
      final group = ids.sublist(
        i,
        math.min(i + _foldersPerQuery, ids.length),
      );
      final inParents = group.map((id) => "'$id' in parents").join(' or ');
      queries.add(_listFiles(
        getHeaders,
        query: "$condition and trashed = false and ($inParents)",
        fields: fields,
      ));
    }

    final results = await Future.wait(queries);
    return [for (final r in results) ...r];
  }

  /// Pide a Drive todos los archivos que cumplan la búsqueda, página por página.
  Future<List<Map<String, dynamic>>> _listFiles(
    HeadersProvider getHeaders, {
    required String query,
    required String fields,
  }) async {
    final result = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'fields': 'nextPageToken, files($fields)',
        'pageSize': '1000',
        if (pageToken != null) 'pageToken': pageToken,
      });

      final response = await _get(getHeaders, uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      result.addAll((data['files'] as List).cast<Map<String, dynamic>>());
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    return result;
  }

  /// GET autenticado: renueva el token si venció y traduce los errores.
  Future<http.Response> _get(HeadersProvider getHeaders, Uri uri) async {
    var headers = await getHeaders();
    if (headers == null) throw const SessionException();
    var response = await http.get(uri, headers: headers).timeout(_timeout);

    if (response.statusCode == 401) {
      debugPrint('Token vencido, renovando...');
      headers = await getHeaders(forceRefresh: true);
      if (headers == null) throw const SessionException();
      response = await http.get(uri, headers: headers).timeout(_timeout);
    }

    if (response.statusCode != 200) {
      debugPrint('Drive respondió ${response.statusCode}: ${response.body}');
      throw DriveException(response.statusCode);
    }
    return response;
  }

  // ---------- Utilidades ----------

  String? _parentOf(Map<String, dynamic> file) {
    final parents = file['parents'] as List?;
    if (parents == null || parents.isEmpty) return null;
    return parents.first as String;
  }

  /// Referencia a una imagen de Drive: "drive:ID:VERSIÓN".
  /// La versión sale de la fecha de modificación, así una imagen cambiada se vuelve a descargar.
  String _coverRef(Map<String, dynamic> file) {
    final modified = (file['modifiedTime'] as String?) ?? '0';
    final version = modified.replaceAll(RegExp(r'[^0-9]'), '');
    return 'drive:${file['id']}:$version';
  }
}