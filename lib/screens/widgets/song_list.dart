import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import 'cover_art.dart';

class SongList extends StatelessWidget {
  final PlayerService player;
  final List<Song> songs;
  final void Function(int index) onTap;

  const SongList({
    super.key,
    required this.player,
    required this.songs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: player.currentSongStream,
      builder: (context, snapshot) {
        final current = snapshot.data;
        return ListView.builder(
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final isCurrent = song == current;
            return ListTile(
              leading: CoverArt(
                seed: song.albumId ?? song.id,
                imageUri: song.coverUri,
                size: 44,
                icon: Icons.music_note,
              ),
              title: Text(song.title),
              subtitle: Text(song.artist),
              trailing: isCurrent ? const Icon(Icons.graphic_eq) : null,
              selected: isCurrent,
              onTap: () => onTap(index),
            );
          },
        );
      },
    );
  }
}