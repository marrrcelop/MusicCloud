import 'package:flutter/material.dart';

enum BackgroundPattern { none, checker }

/// Cómo se dibuja el fondo de un tema transparente.
class ThemeBackground {
  /// Imagen incluida en la app, por ejemplo 'assets/backgrounds/scene.png'.
  /// Si es null, se usa solo el degradado.
  final String? asset;

  /// Repetir la imagen como mosaico en vez de estirarla a toda la pantalla.
  final bool tile;

  /// Tamaño del mosaico (mayor = más pequeño).
  final double tileScale;

  /// Desenfoque de la imagen (0 = nítida).
  final double blur;

  /// Color con el que se tiñe la imagen, y cómo se mezcla.
  final Color? tint;
  final BlendMode tintMode;

  /// Oscurecido de los bordes, de 0 a 1.
  final double vignette;

  /// Patrón dibujado encima de la imagen.
  final BackgroundPattern pattern;
  final double patternOpacity;
  final double patternCell;

  const ThemeBackground({
    this.asset,
    this.tile = false,
    this.tileScale = 2,
    this.blur = 0,
    this.tint,
    this.tintMode = BlendMode.modulate,
    this.vignette = 0,
    this.pattern = BackgroundPattern.none,
    this.patternOpacity = 0.07,
    this.patternCell = 28,
  });
}