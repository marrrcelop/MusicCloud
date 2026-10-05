import 'package:flutter/material.dart';
import '../../models/album.dart';

class AlbumCover extends StatelessWidget {
  final Album album;
  final double size;

  const AlbumCover({super.key, required this.album, this.size = 48});

  Color _colorFor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.45, 0.40).toColor();
  }

  @override
  Widget build(BuildContext context) {
    // Más adelante: si album.coverUri tiene valor, aquí se mostrará la imagen.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorFor(album.id),
        borderRadius: BorderRadius.circular(size * 0.15),
      ),
      child: Icon(Icons.album, color: Colors.white70, size: size * 0.55),
    );
  }
}