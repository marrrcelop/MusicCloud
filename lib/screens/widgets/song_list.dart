import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import 'cover_art.dart';

enum SongAction { edit, trash }

class SongList extends StatelessWidget {
  final PlayerService player;
  final List<Song> songs;
  final void Function(int index) onTap;

  /// Si se indica, cada canción muestra un menú ⋮ con acciones.
  final void Function(Song song, SongAction action)? onAction;

  const SongList({
    super.key,
    required this.player,
    required this.songs,
    required this.onTap,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final handler = onAction;

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
              trailing: (isCurrent || handler != null)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCurrent) const Icon(Icons.graphic_eq),
                        if (handler != null)
                          PopupMenuButton<SongAction>(
                            onSelected: (action) => handler(song, action),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: SongAction.edit,
                                child: Text('Editar datos'),
                              ),
                              PopupMenuItem(
                                value: SongAction.trash,
                                child: Text('Mover a la papelera'),
                              ),
                            ],
                          ),
                      ],
                    )
                  : null,
              selected: isCurrent,
              onTap: () => onTap(index),
            );
          },
        );
      },
    );
  }
}