import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import 'album_cover.dart';

class AlbumList extends StatelessWidget {
  final List<Album> albums;
  final int Function(Album album) countOf;
  final void Function(Album album) onTap;

  const AlbumList({
    super.key,
    required this.albums,
    required this.countOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return ListTile(
          leading: AlbumCover(album: album),
          title: Text(album.name),
          subtitle: Text([
            if (album.artist != null) album.artist!,
            songCountText(countOf(album)),
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(album),
        );
      },
    );
  }
}