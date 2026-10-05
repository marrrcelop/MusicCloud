import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'app_error.dart';

/// Una función que entrega las cabeceras con el token de Google.
typedef HeadersProvider = Future<Map<String, String>?> Function({
  bool forceRefresh,
});

/// Fuente de audio que descarga un archivo de Drive por partes,
/// pidiendo un token vigente en cada petición.
class DriveAudioSource extends StreamAudioSource {
  static final http.Client _client = http.Client();

  final String fileId;
  final HeadersProvider getHeaders;

  DriveAudioSource({
    required this.fileId,
    required this.getHeaders,
    dynamic tag,
  }) : super(tag: tag);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    var response = await _send(start, end, forceRefresh: false);

    // Token vencido: lo renovamos y repetimos la petición una vez.
    if (response.statusCode == 401) {
      debugPrint('Token vencido, renovando...');
      await response.stream.drain<void>();
      response = await _send(start, end, forceRefresh: true);
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.drain<void>();
      throw DriveException(response.statusCode);
    }

    // Tamaño total del archivo: viene en "Content-Range: bytes 0-999/12345"
    int? sourceLength = response.contentLength;
    final contentRange = response.headers['content-range'];
    if (contentRange != null) {
      sourceLength = int.tryParse(contentRange.split('/').last) ?? sourceLength;
    }

    return StreamAudioResponse(
      sourceLength: sourceLength,
      contentLength: response.contentLength,
      offset: start ?? 0,
      stream: response.stream,
      contentType: response.headers['content-type'] ?? 'audio/mpeg',
    );
  }

  Future<http.StreamedResponse> _send(
    int? start,
    int? end, {
    required bool forceRefresh,
  }) async {
    final headers = await getHeaders(forceRefresh: forceRefresh);
    if (headers == null) throw const SessionException();

    final request = http.Request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'alt': 'media',
      }),
    );
    request.headers.addAll(headers);


    if (start != null || end != null) {
      // En just_audio "end" es exclusivo; en HTTP el último byte es inclusivo.
      final last = end != null ? '${end - 1}' : '';
      request.headers['Range'] = 'bytes=${start ?? 0}-$last';
    }

    return _client.send(request).timeout(const Duration(seconds: 20));
  }
}