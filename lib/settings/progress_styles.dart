import 'package:flutter/material.dart';
import '../screens/widgets/progress_bar_data.dart';
import '../screens/widgets/rainbow_progress_bar.dart';

typedef ProgressBarBuilder = Widget Function(
  BuildContext context,
  ProgressBarData data,
);

/// Un estilo de barra de progreso que el usuario puede elegir.
class ProgressStyleSpec {
  final String id;
  final String name;

  /// Si el estilo puede mostrar una imagen elegida por el usuario.
  final bool usesSprite;
  final ProgressBarBuilder build;

  const ProgressStyleSpec({
    required this.id,
    required this.name,
    required this.build,
    this.usesSprite = false,
  });
}

class ProgressStyles {
  static const defaultId = 'classic';

  // Para agregar otro estilo, suma una entrada aquí.
  static final List<ProgressStyleSpec> all = [
    const ProgressStyleSpec(id: 'classic', name: 'Clásica', build: _classic),
    const ProgressStyleSpec(id: 'thick', name: 'Gruesa', build: _thick),
    ProgressStyleSpec(
      id: 'rainbow',
      name: 'Arcoíris (nyan)',
      usesSprite: true,
      build: (context, data) => RainbowProgressBar(data: data),
    ),
  ];

  static ProgressStyleSpec byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);

  static Widget _classic(BuildContext context, ProgressBarData d) {
    return Slider(
      value: d.fraction.clamp(0.0, 1.0).toDouble(),
      onChanged: d.enabled ? d.onChanged : null,
      onChangeEnd: d.enabled ? d.onChangeEnd : null,
    );
  }

  static Widget _thick(BuildContext context, ProgressBarData d) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 14,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
      ),
      child: Slider(
        value: d.fraction.clamp(0.0, 1.0).toDouble(),
        onChanged: d.enabled ? d.onChanged : null,
        onChangeEnd: d.enabled ? d.onChangeEnd : null,
      ),
    );
  }
}