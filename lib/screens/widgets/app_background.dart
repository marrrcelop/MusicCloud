import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointMode;
import 'package:flutter/material.dart';
import '../../settings/app_themes.dart';
import '../../settings/settings_scope.dart';
import '../../settings/theme_background.dart';

/// Fondo detrás de todas las pantallas. Solo se dibuja en los temas transparentes.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final theme = AppThemes.byId(settings.themeId);
    if (!theme.transparent) return const SizedBox.shrink();

    final spec = theme.background ?? const ThemeBackground();
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final px = (media.size.width * media.devicePixelRatio).round();

    // La imagen del usuario (de este tema), si eligió una; si no, la propia del tema.
    final userPath = settings.backgroundPath;
    final ImageProvider? provider = userPath != null
        ? ResizeImage(FileImage(File(userPath)), width: px)
        : (spec.asset != null ? AssetImage(spec.asset!) : null);

    final gradientColors =
        spec.gradient ?? [const Color(0xFF12081F), scheme.primaryContainer];
    final patternPainter = _patternPainter(spec);

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Capa 1: degradado (se ve si no hay imagen o no se pudo abrir).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
            ),
          ),
          // Capa 2: imagen, con tinte y desenfoque si el tema los pide.
          if (provider != null) _image(provider, spec),
          // Capa 3: patrón.
          if (patternPainter != null) CustomPaint(painter: patternPainter),
          // Capa 4: viñeta (bordes oscuros).
          if (spec.vignette > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: spec.vignette),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          // Capa 5: oscurecido general, el deslizador de Personalización.
          ColoredBox(
            color: Colors.black.withValues(alpha: settings.backgroundDim),
          ),
        ],
      ),
    );
  }

  Widget _image(ImageProvider provider, ThemeBackground spec) {
    Widget image = DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: provider,
          fit: spec.tile ? BoxFit.none : BoxFit.cover,
          repeat: spec.tile ? ImageRepeat.repeat : ImageRepeat.noRepeat,
          scale: spec.tile ? spec.tileScale : 1.0,
          filterQuality: FilterQuality.medium,
          colorFilter: spec.tint == null
              ? null
              : ColorFilter.mode(spec.tint!, spec.tintMode),
          onError: (_, __) {}, // si falla, se ve el degradado de abajo
        ),
      ),
    );

    if (spec.blur > 0) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: spec.blur, sigmaY: spec.blur),
        child: image,
      );
    }
    return image;
  }

  CustomPainter? _patternPainter(ThemeBackground spec) {
    final color = spec.patternColor.withValues(alpha: spec.patternOpacity);
    switch (spec.pattern) {
      case BackgroundPattern.none:
        return null;
      case BackgroundPattern.checker:
        return _CheckerPainter(color: color, cell: spec.patternCell);
      case BackgroundPattern.stripes:
        return _StripesPainter(color: color, gap: spec.patternCell);
      case BackgroundPattern.grain:
        return _GrainPainter(
          color: spec.patternColor,
          opacity: spec.patternOpacity,
        );
    }
  }
}

/// Dibuja un tablero de cuadros.
class _CheckerPainter extends CustomPainter {
  final Color color;
  final double cell;

  const _CheckerPainter({required this.color, required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.color != color || old.cell != cell;
}

/// Dibuja rayas diagonales.
class _StripesPainter extends CustomPainter {
  final Color color;
  final double gap;

  const _StripesPainter({required this.color, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = gap * 0.22;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) =>
      old.color != color || old.gap != gap;
}

/// Dibuja grano de película y algunos rayones (estética sucia).
class _GrainPainter extends CustomPainter {
  final Color color;
  final double opacity;

  const _GrainPainter({required this.color, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    // Semilla fija: el grano es siempre el mismo y no parpadea.
    final random = math.Random(7);
    final count = math.min(9000, (size.width * size.height / 45).floor());

    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      (i.isEven ? light : dark).add(point);
    }

    canvas.drawPoints(
      PointMode.points,
      light,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPoints(
      PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: math.min(1.0, opacity * 2.5))
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    final scratch = Paint()
      ..color = color.withValues(alpha: opacity * 0.9)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 16; i++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final length = 20 + random.nextDouble() * 90;
      final angle = random.nextDouble() * math.pi;
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle) * length, math.sin(angle) * length),
        scratch,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.color != color || old.opacity != opacity;
}