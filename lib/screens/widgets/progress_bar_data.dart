import 'package:flutter/material.dart';

/// Lo que necesita cualquier estilo de barra para dibujarse.
class ProgressBarData {
  /// Posición de 0.0 a 1.0.
  final double fraction;
  final bool enabled;
  final String? spritePath;

  /// Se llama mientras el usuario arrastra.
  final ValueChanged<double> onChanged;

  /// Se llama cuando el usuario suelta (hay que saltar a esa posición).
  final ValueChanged<double> onChangeEnd;

  const ProgressBarData({
    required this.fraction,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    this.spritePath,
  });
}