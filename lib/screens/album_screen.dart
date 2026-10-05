import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/library.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import 'widgets/album_cover.dart';
import 'widgets/player_bar.dart';
import 'widgets/song_list.dart';

class AlbumScreen extends StatelessWidget {
  final Album album;
  final List<Song> songs;
  final PlayerService player;
  final Future<void> Function(List<Song> queue, int index) onPlay;

  const AlbumScreen({
    super.key,
    required this.album,
    required this.songs,
    required this.player,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(album.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AlbumCover(album: album, size: 88),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(songCountText(songs.length)),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Reproducir'),
                        onPressed:
                            songs.isEmpty ? null : () => onPlay(songs, 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SongList(
              player: player,
              songs: songs,
              onTap: (index) => onPlay(songs, index),
            ),
          ),
        ],
      ),
      bottomNavigationBar: PlayerBar(player: player),
    );
  }
}