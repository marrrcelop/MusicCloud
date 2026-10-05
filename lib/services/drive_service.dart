import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/library.dart';
import '../models/song.dart';
import 'app_error.dart';
import 'drive_audio_source.dart';

class DriveService {
  static const _timeout = Duration(seconds: 20);
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Descarga la lista de canciones y carpetas, y arma la biblioteca.
  Future<Library> fetchLibrary(HeadersProvider getHeaders) async {
    final folderFiles = await _listFiles(
      getHeaders,
      query: "mimeType = '$_folderMime' and trashed = false",
      fields: 'id, name',
    );
    final songFiles = await _listFiles(
      getHeaders,
      query: "mimeType contains 'audio/' and trashed = false",
      fields: 'id, name, parents',
    );

    final folderNames = {
      for (final f in folderFiles) f['id'] as String: f['name'] as String,
    };

    final songs = [
      for (final f in songFiles)
        Song(
          id: f['id'] as String,
          title: _cleanName(f['name'] as String),
          source: SongSource.drive,
          path: f['id'] as String,
          albumId: (f['parents'] as List?)?.firstOrNull as String?,
        ),
    ];

    return Library.build(songs: songs, folderNames: folderNames);
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

      var headers = await getHeaders();
      if (headers == null) throw const SessionException();
      var response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode == 401) {
        debugPrint('Token vencido al listar, renovando...');
        headers = await getHeaders(forceRefresh: true);
        if (headers == null) throw const SessionException();
        response = await http.get(uri, headers: headers).timeout(_timeout);
      }

      if (response.statusCode != 200) {
        debugPrint('Cuerpo del error de Drive: ${response.body}');
        throw DriveException(response.statusCode);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      result.addAll((data['files'] as List).cast<Map<String, dynamic>>());
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    return result;
  }

  String _cleanName(String name) => name.replaceFirst(RegExp(r'\.[^.]+$'), '');
}