import 'package:flutter/material.dart';
import '../../services/player_service.dart';
import '../../settings/progress_styles.dart';
import '../../settings/settings_scope.dart';
import 'progress_bar_data.dart';

/// Barra de progreso con tiempos. Usa el estilo que el usuario eligió.
class ProgressSlider extends StatefulWidget {
  final PlayerService player;

  const ProgressSlider({super.key, required this.player});

  @override
  State<ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<ProgressSlider> {
  // Valor temporal mientras el usuario arrastra la barra
  double? _dragMs;

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final style = ProgressStyles.byId(settings.progressStyleId);

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
            final shown = Duration(milliseconds: valueMs.round());

            final data = ProgressBarData(
              fraction: valueMs / maxMs,
              enabled: total.inMilliseconds > 0,
              spritePath: settings.spritePath,
              onChanged: (f) => setState(() => _dragMs = f * maxMs),
              onChangeEnd: (f) {
                widget.player.seek(Duration(milliseconds: (f * maxMs).round()));
                setState(() => _dragMs = null);
              },
            );

            return Column(
              children: [
                style.build(context, data),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(_format(shown)), Text(_format(total))],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}