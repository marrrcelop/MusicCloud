import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/cover_cache.dart';

class CoverArt extends StatelessWidget {
  /// Texto del que sale el color (por ejemplo el id del álbum).
  final String seed;
  final String? imageUri;
  final double size;
  final IconData icon;

  const CoverArt({
    super.key,
    required this.seed,
    this.imageUri,
    this.size = 48,
    this.icon = Icons.album,
  });

  Color _colorFor(String text) {
    final hash =
        text.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.45, 0.40).toColor();
  }

  Widget _placeholder() {
    return Container(
      color: _colorFor(seed),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white70, size: size * 0.5),
    );
  }

  Widget _image(BuildContext context, String uri) {
    // Decodificamos la imagen al tamaño necesario: una portada grande
    // dibujada como miniatura no debe gastar memoria de más.
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();

    if (uri.startsWith('drive:')) {
      return _DriveImage(ref: uri, cacheWidth: pixels, placeholder: _placeholder);
    }
    if (uri.startsWith('http')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        cacheWidth: pixels,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return Image.file(
      File(uri),
      fit: BoxFit.cover,
      cacheWidth: pixels,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = imageUri;
    final radius = (size * 0.15).clamp(0.0, 24.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null ? _placeholder() : _image(context, uri),
      ),
    );
  }
}

/// Imagen guardada en Drive: se descarga una vez y luego sale del teléfono.
class _DriveImage extends StatefulWidget {
  final String ref;
  final int cacheWidth;
  final Widget Function() placeholder;

  const _DriveImage({
    required this.ref,
    required this.cacheWidth,
    required this.placeholder,
  });

  @override
  State<_DriveImage> createState() => _DriveImageState();
}

class _DriveImageState extends State<_DriveImage> {
  late Future<File?> _file = CoverCache.instance.resolve(widget.ref);

  @override
  void didUpdateWidget(_DriveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref != widget.ref) {
      _file = CoverCache.instance.resolve(widget.ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return widget.placeholder();
        return Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => widget.placeholder(),
        );
      },
    );
  }
}