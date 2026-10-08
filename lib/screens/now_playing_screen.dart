import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import 'widgets/cover_art.dart';
import 'widgets/progress_slider.dart';

class NowPlayingScreen extends StatelessWidget {
  final PlayerService player;

  const NowPlayingScreen({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: player.currentSongStream,
      initialData: player.currentSong,
      builder: (context, snapshot) {
        final song = snapshot.data;

        if (song == null) {
          // Se cerró la música: salimos de esta pantalla (una sola vez).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold();
        }

        final textTheme = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Minimizar',
              icon: const Icon(Icons.keyboard_arrow_down, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Reproduciendo'),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = constraints.biggest.shortestSide
                            .clamp(0.0, 360.0)
                            .toDouble();
                        return Center(
                          child: CoverArt(
                            seed: song.albumId ?? song.id,
                            imageUri: song.coverUri,
                            size: side,
                            icon: Icons.music_note,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    song.title,
                    style: textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (song.details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      song.details,
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 16),
                  ProgressSlider(player: player),
                  _buildControls(context),
                  const SizedBox(height: 8),
                  _buildVolume(),
                  _buildBoost(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: player.shuffleStream,
          initialData: false,
          builder: (context, snapshot) {
            final shuffleOn = snapshot.data ?? false;
            return IconButton(
              tooltip: 'Aleatorio',
              icon: Icon(
                Icons.shuffle,
                color: shuffleOn ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () => player.setShuffle(!shuffleOn),
            );
          },
        ),
        IconButton(
          tooltip: 'Anterior',
          iconSize: 44,
          icon: const Icon(Icons.skip_previous),
          onPressed: player.previous,
        ),
        StreamBuilder<bool>(
          stream: player.playingStream,
          initialData: false,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              iconSize: 72,
              icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
              onPressed: () => isPlaying ? player.pause() : player.resume(),
            );
          },
        ),
        IconButton(
          tooltip: 'Siguiente',
          iconSize: 44,
          icon: const Icon(Icons.skip_next),
          onPressed: player.next,
        ),
        const SizedBox(width: 48), // aquí irá "repetir" más adelante
      ],
    );
  }

  Widget _buildVolume() {
    return StreamBuilder<double>(
      stream: player.volumeStream,
      initialData: 1.0,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 1.0;
        return Row(
          children: [
            Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
            Expanded(
              child: Slider(value: volume, onChanged: player.setVolume),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBoost() {
    return StreamBuilder<double>(
      stream: player.boostStream,
      initialData: 0.0,
      builder: (context, snapshot) {
        final boost = (snapshot.data ?? 0.0).clamp(0.0, 1.0).toDouble();
        return Row(
          children: [
            const Icon(Icons.graphic_eq),
            Expanded(
              child: Slider(
                value: boost,
                divisions: 10,
                label: boost == 0 ? 'Sin refuerzo' : boost.toStringAsFixed(1),
                onChanged: player.setBoost,
              ),
            ),
          ],
        );
      },
    );
  }
}