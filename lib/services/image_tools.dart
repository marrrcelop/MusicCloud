import 'dart:typed_data';
import 'dart:ui' as ui;

class PreparedImage {
  final Uint8List bytes;
  final String mimeType;
  final String extension;

  const PreparedImage(this.bytes, this.mimeType, this.extension);
}

String _mimeFor(String ext) {
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    default:
      return 'image/jpeg';
  }
}

/// Si la imagen tiene un lado mayor a [maxSide] píxeles, la reduce.
/// Si ya es pequeña, se sube tal cual.
Future<PreparedImage> prepareCover(
  Uint8List original,
  String extension, {
  int maxSide = 1200,
}) async {
  final ext = extension.toLowerCase();
  final buffer = await ui.ImmutableBuffer.fromUint8List(original);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  try {
    final wide = descriptor.width >= descriptor.height;
    final longest = wide ? descriptor.width : descriptor.height;
    if (longest <= maxSide) {
      return PreparedImage(original, _mimeFor(ext), ext);
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: wide ? maxSide : null,
      targetHeight: wide ? null : maxSide,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();

    if (data == null) return PreparedImage(original, _mimeFor(ext), ext);
    return PreparedImage(data.buffer.asUint8List(), 'image/png', 'png');
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}