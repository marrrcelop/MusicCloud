import 'package:flutter/material.dart';
import '../../models/album.dart';
import 'cover_art.dart';

class AlbumCover extends StatelessWidget {
  final Album album;
  final double size;

  const AlbumCover({super.key, required this.album, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return CoverArt(seed: album.id, imageUri: album.coverUri, size: size);
  }
}