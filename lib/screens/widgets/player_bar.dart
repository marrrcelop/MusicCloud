import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';

class PlayerBar extends StatefulWidget {
  final PlayerService player;

  const PlayerBar({super.key, required this.player});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  // Valor temporal mientras el usuario arrastra la barra
  double? _dragMs;

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: widget.player.currentSongStream,
      builder: (context, snapshot) {
        final song = snapshot.data;
        if (song == null) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                                    Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(song.artist),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar reproductor',
                        icon: const Icon(Icons.close),
                        onPressed: widget.player.close,
                      ),
                    ],
                  ),
                  _buildProgress(),
                  _buildControls(),
                  _buildVolume(),
                  _buildBoost(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StreamBuilder<bool>(
          stream: widget.player.shuffleStream,
          initialData: false,
          builder: (context, snapshot) {
            final shuffleOn = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                Icons.shuffle,
                color: shuffleOn ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () => widget.player.setShuffle(!shuffleOn),
            );
          },
        ),
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_previous),
          onPressed: widget.player.previous,
        ),
        StreamBuilder<bool>(
          stream: widget.player.playingStream,
          initialData: false,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return IconButton(
              iconSize: 48,
              icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
              onPressed: () =>
                  isPlaying ? widget.player.pause() : widget.player.resume(),
            );
          },
        ),
        IconButton(
          iconSize: 36,
          icon: const Icon(Icons.skip_next),
          onPressed: widget.player.next,
        ),
      ],
    );
  }

  Widget _buildProgress() {
    return StreamBuilder<Duration?>(
      stream: widget.player.durationStream,
      builder: (context, durationSnap) {
        final total = durationSnap.data ?? Duration.zero;
        final maxMs =
            total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;

        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final valueMs = (_dragMs ?? position.inMilliseconds.toDouble())
                .clamp(0.0, maxMs)
                .toDouble();

            return Row(
              children: [
                Text(_format(position)),
                Expanded(
                  child: Slider(
                    value: valueMs,
                    max: maxMs,
                    onChanged: total.inMilliseconds > 0
                        ? (v) => setState(() => _dragMs = v)
                        : null,
                    onChangeEnd: (v) {
                      widget.player.seek(Duration(milliseconds: v.round()));
                      setState(() => _dragMs = null);
                    },
                  ),
                ),
                Text(_format(total)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVolume() {
    return StreamBuilder<double>(
      stream: widget.player.volumeStream,
      initialData: 1.0,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 1.0;
        return Row(
          children: [
            Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
            Expanded(
              child: Slider(
                value: volume,
                onChanged: (v) => widget.player.setVolume(v),
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildBoost() {
    return StreamBuilder<double>(
      stream: widget.player.boostStream,
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
                onChanged: widget.player.setBoost,
              ),
            ),
          ],
        );
      },
    );
  }
}