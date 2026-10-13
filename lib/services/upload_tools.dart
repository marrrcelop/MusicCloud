import 'dart:io';

/// Se lanza cuando el usuario cancela una subida en curso.
class UploadCancelled implements Exception {
  const UploadCancelled();

  @override
  String toString() => 'UploadCancelled';
}

/// Un archivo de audio listo para subir a Drive.
class UploadItem {
  final String path;
  final String name;
  final int size;
  final String mimeType;

  const UploadItem({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });
}

/// Resultado de subir varios archivos.
class UploadReport {
  final int uploaded;

  /// Archivos que no se subieron porque el álbum ya tenía uno con ese nombre.
  final List<String> skipped;

  /// Archivos que fallaron, con el motivo.
  final List<String> failed;
  final bool cancelled;

  const UploadReport({
    required this.uploaded,
    required this.skipped,
    required this.failed,
    required this.cancelled,
  });
}

const _audioMime = <String, String>{
  'mp3': 'audio/mpeg',
  'flac': 'audio/flac',
  'wav': 'audio/wav',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/ogg',
  'wma': 'audio/x-ms-wma',
  'aiff': 'audio/aiff',
  'aif': 'audio/aiff',
  'weba': 'audio/webm',
};

String? _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

/// Adivina el formato leyendo los primeros bytes del archivo.
Future<String?> _detectExtension(String path) async {
  final file = await File(path).open();
  try {
    final head = await file.read(12);

    bool starts(List<int> signature, [int offset = 0]) {
      if (head.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (head[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (starts([0x66, 0x4C, 0x61, 0x43])) return 'flac'; // "fLaC"
    if (starts([0x49, 0x44, 0x33])) return 'mp3'; // "ID3"
    if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
      return 'mp3'; // MP3 sin etiqueta ID3
    }
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x41, 0x56, 0x45], 8)) {
      return 'wav'; // "RIFF....WAVE"
    }
    if (starts([0x4F, 0x67, 0x67, 0x53])) return 'ogg'; // "OggS"
    if (starts([0x66, 0x74, 0x79, 0x70], 4)) return 'm4a'; // "....ftyp"
    return null;
  } finally {
    await file.close();
  }
}

/// Prepara un archivo elegido para subirlo. Devuelve null si no se puede
/// (está vacío o no se reconoce como audio).
Future<UploadItem?> buildUploadItem(String path, String pickedName) async {
  final size = await File(path).length();
  if (size == 0) return null;

  var name = pickedName;
  var ext = _extensionOf(name);
  if (ext == null || !_audioMime.containsKey(ext)) {
    // Algunos selectores entregan el nombre sin extensión: la deducimos del contenido.
    ext = await _detectExtension(path);
    if (ext == null) return null;
    name = '$name.$ext';
  }

  return UploadItem(
    path: path,
    name: name,
    size: size,
    mimeType: _audioMime[ext]!,
  );
}

/// "1,5 MB", "230 KB"...
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}