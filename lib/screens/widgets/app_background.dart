import 'dart:io';
import 'dart:ui' show ImageFilter;
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

    // La imagen del usuario, si eligió una; si no, la propia del tema.
    final userPath = settings.backgroundPath;
    final ImageProvider? provider = userPath != null
        ? ResizeImage(FileImage(File(userPath)), width: px)
        : (spec.asset != null ? AssetImage(spec.asset!) : null);

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
                colors: [const Color(0xFF12081F), scheme.primaryContainer],
              ),
            ),
          ),
          // Capa 2: imagen, con tinte y desenfoque si el tema los pide.
          if (provider != null) _image(provider, spec),
          // Capa 3: patrón.
          if (spec.pattern == BackgroundPattern.checker)
            CustomPaint(
              painter: _CheckerPainter(
                color: Colors.white.withValues(alpha: spec.patternOpacity),
                cell: spec.patternCell,
              ),
            ),
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