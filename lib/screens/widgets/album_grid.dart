import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import 'album_cover.dart';

/// Álbumes en cuadrícula, con su portada grande.
class AlbumGrid extends StatelessWidget {
  final List<Album> albums;
  final int Function(Album album) countOf;
  final void Function(Album album) onTap;

  const AlbumGrid({
    super.key,
    required this.albums,
    required this.countOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final subtitle = [
          if (album.artist != null) album.artist!,
          songCountText(countOf(album)),
        ].join(' · ');

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La portada ocupa el espacio que dejan los textos (así nunca desborda).
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = math.min(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return Align(
                      alignment: Alignment.topLeft,
                      child: AlbumCover(album: album, size: side),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}