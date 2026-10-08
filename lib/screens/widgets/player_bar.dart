import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../screens/now_playing_screen.dart';
import '../../services/player_service.dart';
import 'cover_art.dart';

/// Barra compacta de abajo. Al tocarla se abre la pantalla completa.
class PlayerBar extends StatelessWidget {
  final PlayerService player;

  const PlayerBar({super.key, required this.player});

  void _openNowPlaying(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true, // sube desde abajo
      builder: (_) => NowPlayingScreen(player: player),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: player.currentSongStream,
      initialData: player.currentSong,
      builder: (context, snapshot) {
        final song = snapshot.data;
        if (song == null) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => _openNowPlaying(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniProgress(player: player),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      children: [
                        CoverArt(
                          seed: song.albumId ?? song.id,
                          imageUri: song.coverUri,
                          size: 44,
                          icon: Icons.music_note,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        StreamBuilder<bool>(
                          stream: player.playingStream,
                          initialData: false,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data ?? false;
                            return IconButton(
                              iconSize: 36,
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                              ),
                              onPressed: () =>
                                  isPlaying ? player.pause() : player.resume(),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Cerrar reproductor',
                          icon: const Icon(Icons.close),
                          onPressed: player.close,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Línea fina de progreso en el borde superior de la barra.
class _MiniProgress extends StatelessWidget {
  final PlayerService player;

  const _MiniProgress({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data?.inMilliseconds ?? 0;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data?.inMilliseconds ?? 0;
            final value =
                total > 0 ? (position / total).clamp(0.0, 1.0).toDouble() : 0.0;
            return LinearProgressIndicator(value: value, minHeight: 2);
          },
        );
      },
    );
  }
}