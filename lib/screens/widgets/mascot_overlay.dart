import 'dart:io';
import 'package:flutter/material.dart';
import '../../settings/settings_scope.dart';

/// La mascota opcional. Flota sobre toda la app y no bloquea los toques.
class MascotOverlay extends StatelessWidget {
  const MascotOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final path = settings.mascotPath;

    if (!settings.mascotEnabled || path == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        // Los toques la atraviesan: no estorba a la lista que haya debajo.
        child: Align(
          // Alignment va de -1 (izquierda o arriba) a 1 (derecha o abajo).
          alignment: Alignment(
            settings.mascotDx * 2 - 1,
            settings.mascotDy * 2 - 1,
          ),
          child: Image.file(
            File(path),
            width: settings.mascotSize,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}