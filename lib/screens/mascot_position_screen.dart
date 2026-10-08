import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../settings/settings_scope.dart';

/// Pantalla para arrastrar la mascota. Cubre toda la pantalla, así lo que ves
/// coincide con la posición real. La mascota que se mueve es la de la app.
class MascotPositionScreen extends StatelessWidget {
  const MascotPositionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final half = settings.mascotSize / 2;

    void moveTo(Offset p) {
      // Dejamos el dedo aproximadamente en el centro de la mascota.
      final spanX = math.max(1.0, size.width - half * 2);
      final spanY = math.max(1.0, size.height - half * 2);
      final dx = ((p.dx - half) / spanX).clamp(0.0, 1.0).toDouble();
      final dy = ((p.dy - half) / spanY).clamp(0.0, 1.0).toDouble();
      settings.moveMascot(dx, dy);
    }

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => moveTo(d.localPosition),
        onPanUpdate: (d) => moveTo(d.localPosition),
        onPanEnd: (_) => settings.commitMascotPosition(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  'Arrastra en cualquier parte de la pantalla para colocar la mascota.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: settings.resetMascotPosition,
                      child: const Text('Restablecer'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Listo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}