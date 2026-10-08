import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'drive_audio_source.dart';
import 'drive_service.dart';

/// Descarga las imágenes de Drive una sola vez y las guarda en el teléfono.
class CoverCache {
  CoverCache._();
  static final CoverCache instance = CoverCache._();

  /// La pantalla principal lo asigna al iniciar (así la caché puede pedir el token).
  HeadersProvider? getHeaders;

  final DriveService _drive = DriveService();
  final Map<String, Future<File?>> _inFlight = {};
  Directory? _dir;

  /// Devuelve el archivo local de una referencia "drive:ID:VERSIÓN".
  /// Si todavía no está en el teléfono, lo descarga. Devuelve null si no se pudo.
  Future<File?> resolve(String ref) {
    final running = _inFlight[ref];
    if (running != null) return running; // ya se está descargando

    final future = _load(ref).whenComplete(() {
      _inFlight.remove(ref);
    });
    _inFlight[ref] = future;
    return future;
  }

  Future<File?> _load(String ref) async {
    final parts = ref.split(':'); // drive : id : versión
    if (parts.length < 3 || parts.first != 'drive') return null;
    final id = parts[1];
    final version = parts[2];

    final dir = await _coversDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}cover_${id}_$version.img',
    );
    if (await file.exists()) return file;

    final headers = getHeaders;
    if (headers == null) return null;

    try {
      final bytes = await _drive.downloadBytes(headers, id);
      // Se guarda primero con otro nombre, para no dejar archivos a medias.
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      await _deleteOldVersions(dir, id, keep: file.path);
      return file;
    } catch (e) {
      debugPrint('No se pudo descargar la portada $id: $e');
      return null;
    }
  }

  Future<Directory> _coversDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}covers');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Borra las versiones anteriores de una misma imagen.
  Future<void> _deleteOldVersions(
    Directory dir,
    String id, {
    required String keep,
  }) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path != keep &&
            entity.uri.pathSegments.last.startsWith('cover_${id}_')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Limpiar es opcional: si falla, no pasa nada.
    }
  }
}