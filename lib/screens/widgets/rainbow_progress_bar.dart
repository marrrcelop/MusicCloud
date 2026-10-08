import 'dart:io';
import 'package:flutter/material.dart';
import 'progress_bar_data.dart';

/// Barra con estela de arcoíris. En la punta muestra una imagen elegida por el usuario.
class RainbowProgressBar extends StatelessWidget {
  final ProgressBarData data;

  const RainbowProgressBar({super.key, required this.data});

  static const double _height = 40;
  static const double _barHeight = 12;
  static const double _spriteWidth = 64;

  @override
  Widget build(BuildContext context) {
    final trackColor = Theme.of(context).colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final fraction = data.fraction.clamp(0.0, 1.0).toDouble();
          final headX = width * fraction;
          final sprite = data.spritePath;

          double toFraction(double dx) =>
              width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0).toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: data.enabled
                ? (d) => data.onChangeEnd(toFraction(d.localPosition.dx))
                : null,
            onHorizontalDragUpdate: data.enabled
                ? (d) => data.onChanged(toFraction(d.localPosition.dx))
                : null,
            onHorizontalDragEnd:
                data.enabled ? (_) => data.onChangeEnd(data.fraction) : null,
            child: SizedBox(
              height: _height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (_height - _barHeight) / 2,
                    height: _barHeight,
                    child: CustomPaint(
                      painter: _RainbowPainter(
                        headX: headX,
                        trackColor: trackColor,
                      ),
                    ),
                  ),
                  Positioned(
                    left: headX - _spriteWidth / 2,
                    top: 0,
                    width: _spriteWidth,
                    height: _height,
                    child: sprite == null
                        ? const _DefaultHead()
                        : Image.file(
                            File(sprite),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => const _DefaultHead(),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cabeza por defecto cuando no hay imagen elegida: un círculo blanco.
class _DefaultHead extends StatelessWidget {
  const _DefaultHead();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26, width: 2),
        ),
      ),
    );
  }
}

class _RainbowPainter extends CustomPainter {
  final double headX;
  final Color trackColor;

  const _RainbowPainter({required this.headX, required this.trackColor});

  static const _colors = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF0A84FF),
    Color(0xFFAF52DE),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );

    // Pista de fondo
    canvas.drawRRect(rrect, Paint()..color = trackColor);

    // Franjas de colores hasta la posición actual
    canvas.save();
    canvas.clipRRect(rrect);
    final bandHeight = size.height / _colors.length;
    for (var i = 0; i < _colors.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandHeight, headX, bandHeight + 0.5),
        Paint()..color = _colors[i],
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RainbowPainter old) =>
      old.headX != headX || old.trackColor != trackColor;
}