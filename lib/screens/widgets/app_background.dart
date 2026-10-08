import 'dart:io';
import 'package:flutter/material.dart';
import '../../settings/app_themes.dart';
import '../../settings/settings_scope.dart';

/// Fondo detrás de todas las pantallas. Solo se dibuja en los temas transparentes.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    if (!AppThemes.byId(settings.themeId).transparent) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final path = settings.backgroundPath;

    // Degradado por defecto (y si la imagen no se puede abrir).
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF12081F), scheme.primaryContainer],
        ),
      ),
    );

    if (path == null) return Positioned.fill(child: gradient);

    // Decodificamos la imagen al ancho de la pantalla, no al de la foto original.
    final media = MediaQuery.of(context);
    final width = (media.size.width * media.devicePixelRatio).round();

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: width,
            errorBuilder: (_, __, ___) => gradient,
          ),
          // Capa oscura para que el texto se lea sobre cualquier imagen.
          ColoredBox(
            color: Colors.black.withValues(alpha: settings.backgroundDim),
          ),
        ],
      ),
    );
  }
}