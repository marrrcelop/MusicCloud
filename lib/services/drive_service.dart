import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'drive_audio_source.dart';

class DriveService {
  Future<List<Song>> fetchSongs(HeadersProvider getHeaders) async {
    final songs = <Song>[];
    String? pageToken;

    do {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "mimeType contains 'audio/' and trashed = false",
        'fields': 'nextPageToken, files(id, name, mimeType, parents)',
        'pageSize': '100',
        if (pageToken != null) 'pageToken': pageToken,
      });

      var headers = await getHeaders();
      if (headers == null) throw Exception('No hay sesión de Google activa');
      var response = await http.get(uri, headers: headers);

      if (response.statusCode == 401) {
        debugPrint('Token vencido al listar, renovando...');
        headers = await getHeaders(forceRefresh: true);
        if (headers == null) throw Exception('No hay sesión de Google activa');
        response = await http.get(uri, headers: headers);
      }

      if (response.statusCode != 200) {
        debugPrint('Cuerpo del error de Drive: ${response.body}');
        throw Exception('Drive respondió ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final files = (data['files'] as List).cast<Map<String, dynamic>>();

      for (final f in files) {
        final id = f['id'] as String;
        songs.add(Song(
          id: id,
          title: _cleanName(f['name'] as String),
          source: SongSource.drive,
          path: id,
          albumId: (f['parents'] as List?)?.firstOrNull as String?,
        ));
      }

      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    return songs;
  }

  String _cleanName(String name) => name.replaceFirst(RegExp(r'\.[^.]+$'), '');
}