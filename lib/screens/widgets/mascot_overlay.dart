import 'dart:io';
import 'package:flutter/material.dart';
import '../../settings/settings_scope.dart';

/// La mascota opcional. Se coloca en el espacio del botón flotante del Scaffold,
/// que Flutter ya ubica abajo a la derecha, por encima de la barra del reproductor.
class MascotOverlay extends StatelessWidget {
  const MascotOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final path = settings.mascotPath;

    if (!settings.mascotEnabled || path == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      // Los toques la atraviesan: no estorba a la lista que haya debajo.
      child: Image.file(
        File(path),
        width: settings.mascotSize,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}