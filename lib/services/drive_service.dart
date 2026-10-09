import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'library_cache.dart';

/// Resultado de leer Drive: la biblioteca y los album.json conocidos.
class LibraryResult {
  final Library library;
  final Map<String, CachedMeta> metas;

  const LibraryResult(this.library, this.metas);
}

class DriveService {
  static const _timeout = Duration(seconds: 25);
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Cuántas carpetas se consultan en cada petición a Drive.
  static const _foldersPerQuery = 10;

  /// Cuántas consultas de carpetas se hacen a la vez.
  static const _parallelQueries = 3;

  /// Cuántos album.json se descargan a la vez.
  static const _parallelDownloads = 6;

  /// Intentos por petición antes de rendirse.
  static const _maxAttempts = 3;

  /// Un solo cliente HTTP para todas las peticiones: reutiliza las conexiones
  /// en vez de abrir y negociar una nueva (con su cifrado) en cada petición.
  static final http.Client _client = http.Client();

  /// Lee Drive y arma la biblioteca.
  ///
  /// [cachedMetas]: album.json de la vez anterior; los que no cambiaron no se
  /// vuelven a descargar.
  /// [onBasic]: se llama en cuanto se conocen las canciones y carpetas, antes de
  /// tener portadas y datos, para poder mostrar algo cuanto antes.
  Future<LibraryResult> fetchLibrary(
    HeadersProvider getHeaders, {
    Map<String, CachedMeta> cachedMetas = const {},
    void Function(Library basic)? onBasic,
  }) async {
    final watch = Stopwatch()..start();

    // 1) Imprescindible: canciones y carpetas. Si esto falla, se avisa del error.
    final basics = await Future.wait([
      _listFiles(
        getHeaders,
        query: "mimeType contains 'audio/' and trashed = false",
        fields: 'id, name, parents',
      ),
      _listFiles(
        getHeaders,
        query: "mimeType = '$_folderMime' and trashed = false",
        fields: 'id, name',
      ),
    ]);
    final audioFiles = basics[0];
    final folderFiles = basics[1];
    debugPrint(
      'Drive: ${audioFiles.length} canciones y ${folderFiles.length} carpetas '
      '(${watch.elapsedMilliseconds} ms)',
    );

    final folderNames = {
      for (final f in folderFiles) f['id'] as String: f['name'] as String,
    };

    // Solo miramos imágenes y datos dentro de las carpetas que tienen música.
    final parentIds = <String>{
      for (final f in audioFiles)
        if (_parentOf(f) != null) _parentOf(f)!,
    };

    // Primera versión, sin portadas ni datos, para mostrar algo enseguida.
    onBasic?.call(_assemble(
      audioFiles: audioFiles,
      folderNames: folderNames,
      parentIds: parentIds,
      metaByParent: const {},
      albumCovers: const {},
      songCovers: const {},
      incomplete: false,
    ));

    // 2) Opcional: portadas y datos. Si fallan, la biblioteca carga igual.
    var incomplete = false;

    Future<List<Map<String, dynamic>>> optional(
      String what,
      Future<List<Map<String, dynamic>>> Function() load,
    ) async {
      try {
        return await load();
      } catch (e) {
        incomplete = true;
        debugPrint('No se pudieron leer $what: $e');
        return [];
      }
    }

    final found = await Future.wait([
      // Todos los album.json en una sola búsqueda (son pocos y se buscan por nombre).
      optional('los datos de los álbumes', () async {
        final all = await _listFiles(
          getHeaders,
          query: "name = 'album.json' and trashed = false",
          fields: 'id, parents, modifiedTime',
        );
        return [
          for (final f in all)
            if (parentIds.contains(_parentOf(f))) f,
        ];
      }),
      // Las imágenes sí se buscan carpeta por carpeta, para no recorrer tus fotos.
      optional(
        'las portadas',
        () => _listInParents(
          getHeaders,
          parentIds,
          condition: "mimeType contains 'image/'",
          fields: 'id, name, parents, modifiedTime',
        ),
      ),
    ]);
    final metaFiles = found[0];
    final imageFiles = found[1];
    debugPrint(
      'Drive: ${imageFiles.length} imágenes y ${metaFiles.length} album.json '
      '(${watch.elapsedMilliseconds} ms)',
    );

    // 3) Datos: reutilizamos los que no cambiaron y descargamos solo los demás.
    final metas = <String, CachedMeta>{};
    final toDownload = <Map<String, dynamic>>[];
    for (final f in metaFiles) {
      final parent = _parentOf(f);
      if (parent == null) continue;
      final id = f['id'] as String;
      final modified = (f['modifiedTime'] as String?) ?? '';
      final cached = cachedMetas[id];
      if (cached != null &&
          cached.modified == modified &&
          cached.parent == parent) {
        metas[id] = cached; // sin descargar
      } else {
        toDownload.add(f);
      }
    }
    debugPrint(
      'Drive: ${metas.length} album.json ya guardados, '
      '${toDownload.length} por descargar',
    );

    Future<MapEntry<String, CachedMeta>?> download(
      Map<String, dynamic> f,
    ) async {
      final id = f['id'] as String;
      try {
        final bytes = await downloadBytes(getHeaders, id);
        final text = utf8.decode(bytes, allowMalformed: true);
        AlbumMeta.fromJsonString(text); // solo para comprobar que está bien escrito
        return MapEntry(
          id,
          CachedMeta(
            parent: _parentOf(f)!,
            modified: (f['modifiedTime'] as String?) ?? '',
            text: text,
          ),
        );
      } on FormatException catch (e) {
        // Un album.json mal escrito es un error tuyo, no de la red.
        debugPrint('album.json mal escrito ($id): ${e.message}');
        return null;
      } catch (e) {
        incomplete = true;
        debugPrint('No se pudo descargar album.json ($id): $e');
        return null;
      }
    }

    final downloaded = await _runLimited<MapEntry<String, CachedMeta>?>(
      [for (final f in toDownload) () => download(f)],
      _parallelDownloads,
    );
    for (final entry in downloaded) {
      if (entry != null) metas[entry.key] = entry.value;
    }

    final metaByParent = <String, AlbumMeta>{};
    for (final entry in metas.values) {
      try {
        metaByParent.putIfAbsent(
          entry.parent,
          () => AlbumMeta.fromJsonString(entry.text),
        );
      } catch (_) {
        // Ya se comprobó al descargarlo; no debería pasar.
      }
    }

    // 4) Índice de imágenes: portada del álbum y portada propia de cada canción.
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

    final library = _assemble(
      audioFiles: audioFiles,
      folderNames: folderNames,
      parentIds: parentIds,
      metaByParent: metaByParent,
      albumCovers: albumCovers,
      songCovers: songCovers,
      incomplete: incomplete,
    );
    debugPrint('Drive: biblioteca lista (${watch.elapsedMilliseconds} ms)');
    return LibraryResult(library, metas);
  }

  /// Une canciones, carpetas, portadas y datos en una biblioteca.
  Library _assemble({
    required List<Map<String, dynamic>> audioFiles,
    required Map<String, String> folderNames,
    required Set<String> parentIds,
    required Map<String, AlbumMeta> metaByParent,
    required Map<String, String> albumCovers,
    required Map<String, String> songCovers,
    required bool incomplete,
  }) {
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
      final albumMeta = parent == null ? null : metaByParent[parent];
      final songMeta = albumMeta?.songFor(fileName);
      final ownCover = parent == null
          ? null
          : songCovers['$parent|${baseName(fileName).toLowerCase()}'];

      songs.add(Song(
        id: id,
        title: songMeta?.title ?? baseName(fileName),
        artist: songMeta?.artist ?? albumMeta?.artist,
        source: SongSource.drive,
        path: id,
        fileName: fileName,
        albumId: parent,
        albumName: album?.name,
        coverUri: ownCover ?? album?.coverUri,
        genre: songMeta?.genre ?? albumMeta?.genre,
        year: songMeta?.year ?? albumMeta?.year,
      ));
    }

    return Library.build(
      songs: songs,
      folders: folders,
      incomplete: incomplete,
    );
  }

  /// Descarga el contenido de un archivo de Drive (imágenes, album.json...).
  Future<Uint8List> downloadBytes(
    HeadersProvider getHeaders,
    String fileId,
  ) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
    });
    final response = await _get(getHeaders, uri);
    return response.bodyBytes;
  }

  // ---------- Consultas a Drive ----------

  /// Ejecuta las tareas de a [limit] a la vez y devuelve todos los resultados.
  Future<List<T>> _runLimited<T>(
    List<Future<T> Function()> tasks,
    int limit,
  ) async {
    final results = <T>[];
    for (var i = 0; i < tasks.length; i += limit) {
      final batch = tasks.sublist(i, math.min(i + limit, tasks.length));
      results.addAll(await Future.wait(batch.map((task) => task())));
    }
    return results;
  }

  /// Busca archivos que cumplan una condición y estén en alguna de esas carpetas.
  Future<List<Map<String, dynamic>>> _listInParents(
    HeadersProvider getHeaders,
    Set<String> parentIds, {
    required String condition,
    required String fields,
  }) async {
    final ids = parentIds.toList();
    final tasks = <Future<List<Map<String, dynamic>>> Function()>[];

    for (var i = 0; i < ids.length; i += _foldersPerQuery) {
      final group = ids.sublist(
        i,
        math.min(i + _foldersPerQuery, ids.length),
      );
      final inParents = group.map((id) => "'$id' in parents").join(' or ');
      tasks.add(() => _listFiles(
            getHeaders,
            query: "$condition and trashed = false and ($inParents)",
            fields: fields,
          ));
    }

    final results = await _runLimited(tasks, _parallelQueries);
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

  /// GET autenticado, con reintentos si la red falla o Drive está ocupado.
  Future<http.Response> _get(HeadersProvider getHeaders, Uri uri) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _getOnce(getHeaders, uri);
      } catch (e) {
        final temporary = e is TimeoutException ||
            e is SocketException ||
            e is http.ClientException ||
            (e is DriveException &&
                (e.statusCode == 429 || e.statusCode >= 500));
        if (!temporary || attempt >= _maxAttempts) rethrow;

        debugPrint(
          'Reintentando ($attempt/$_maxAttempts) ${_describe(uri)}: $e',
        );
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// Un solo intento: renueva el token si venció y traduce los errores.
  Future<http.Response> _getOnce(HeadersProvider getHeaders, Uri uri) async {
    var headers = await getHeaders();
    if (headers == null) throw const SessionException();
    var response = await _client.get(uri, headers: headers).timeout(_timeout);

    if (response.statusCode == 401) {
      debugPrint('Token vencido, renovando...');
      headers = await getHeaders(forceRefresh: true);
      if (headers == null) throw const SessionException();
      response = await _client.get(uri, headers: headers).timeout(_timeout);
    }

    if (response.statusCode != 200) {
      debugPrint(
        'Drive respondió ${response.statusCode} a ${_describe(uri)}: '
        '${response.body}',
      );
      throw DriveException(response.statusCode);
    }
    return response;
  }

  // ---------- Utilidades ----------

  /// Resumen corto de una petición, para los mensajes de la terminal.
  String _describe(Uri uri) {
    final q = uri.queryParameters['q'];
    if (q == null) return uri.path;
    return '${uri.path} q=${q.length > 90 ? '${q.substring(0, 90)}...' : q}';
  }

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