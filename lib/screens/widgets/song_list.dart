import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';

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
              leading: Icon(
                isCurrent
                    ? Icons.graphic_eq
                    : song.source == SongSource.drive
                        ? Icons.cloud
                        : Icons.phone_android,
              ),
              title: Text(song.title),
              subtitle: Text(song.artist),
              selected: isCurrent,
              onTap: () => onTap(index),
            );
          },
        );
      },
    );
  }
}