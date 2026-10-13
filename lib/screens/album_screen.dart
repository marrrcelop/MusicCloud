import 'package:flutter/material.dart';
import '../models/album.dart';
import '../models/library.dart';
import '../models/song.dart';
import '../services/library_repository.dart';
import '../services/library_view_controller.dart';
import '../services/player_service.dart';
import 'widgets/album_cover.dart';
import 'widgets/library_actions.dart';
import 'widgets/player_bar.dart';
import 'widgets/song_list.dart';
import 'album_edit_screen.dart';

enum _AlbumMenu { add, edit, trash }

class AlbumScreen extends StatelessWidget {
  final String albumId;
  final LibraryRepository repo;
  final LibraryViewController view;
  final PlayerService player;
  final Future<void> Function(List<Song> queue, int index) onPlay;
  final Future<void> Function(List<Song> queue) onShuffle;
  final LibraryActions actions;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.repo,
    required this.view,
    required this.player,
    required this.onPlay,
    required this.onShuffle,
    required this.actions,
  });

  void _popIfCurrent(BuildContext context) {
    if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onMenu(
    BuildContext context,
    Album album,
    _AlbumMenu action,
  ) async {
    switch (action) {
      case _AlbumMenu.add:
        await actions.addSongs(context, album);
      case _AlbumMenu.edit:
        if (!actions.requireOnline()) return;
        await Navigator.of(context).push(MaterialPageRoute<bool>(
          builder: (_) => AlbumEditScreen(
            album: album,
            repo: repo,
            actions: actions,
          ),
        ));
      case _AlbumMenu.trash:
        final deleted = await actions.trashAlbum(context, album);
        if (deleted) _popIfCurrent(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repo, view]),
      builder: (context, _) {
        final library = repo.library;
        Album? album;
        if (library != null) {
          for (final a in library.albums) {
            if (a.id == albumId) album = a;
          }
        }

        if (library == null || album == null) {
          // El álbum ya no existe (por ejemplo, se movió a la papelera): salimos.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _popIfCurrent(context);
          });
          return const Scaffold();
        }

        final songs = view.viewOf(library).songsOf(albumId);
        final isEmptyAlbum = library.songsOf(albumId).isEmpty;
        return _buildScreen(context, album, songs, isEmptyAlbum);
      },
    );
  }

  Widget _buildScreen(
    BuildContext context,
    Album album,
    List<Song> songs,
    bool isEmptyAlbum,
  ) {
    final editable = albumId != Library.noAlbumId;

    return Scaffold(
      appBar: AppBar(
        title: Text(album.name),
        actions: [
          if (editable)
            PopupMenuButton<_AlbumMenu>(
              onSelected: (action) => _onMenu(context, album, action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _AlbumMenu.add,
                  child: Text('Agregar canciones'),
                ),
                PopupMenuItem(
                  value: _AlbumMenu.edit,
                  child: Text('Editar álbum'),
                ),
                PopupMenuItem(
                  value: _AlbumMenu.trash,
                  child: Text('Mover a la papelera'),
                ),
              ],
            ),
        ],
      ),
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
                      if (album.details.isNotEmpty)
                        Text(
                          album.details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Reproducir'),
                            onPressed:
                                songs.isEmpty ? null : () => onPlay(songs, 0),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.shuffle),
                            label: const Text('Aleatorio'),
                            onPressed:
                                songs.isEmpty ? null : () => onShuffle(songs),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: songs.isEmpty
                ? _buildEmpty(context, album, isEmptyAlbum, editable)
                : SongList(
                    player: player,
                    songs: songs,
                    onTap: (index) => onPlay(songs, index),
                    onAction: (song, action) =>
                        actions.handleSong(context, song, action),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: PlayerBar(player: player),
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    Album album,
    bool isEmptyAlbum,
    bool editable,
  ) {
    if (!isEmptyAlbum) {
      return const Center(
        child: Text('Ninguna canción coincide con la búsqueda o los filtros.'),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 64),
            const SizedBox(height: 16),
            const Text('Este álbum está vacío.'),
            if (editable) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Agregar canciones'),
                onPressed: () => actions.addSongs(context, album),
              ),
              const SizedBox(height: 8),
              Text(
                'También puedes mover canciones desde otro álbum '
                '(menú ⋮ de cada canción).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}