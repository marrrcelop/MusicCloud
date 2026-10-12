import 'package:flutter/material.dart';
import 'app_fonts.dart';
import 'theme_background.dart';

/// Un tema completo que el usuario puede elegir.
class AppThemeSpec {
  final String id;
  final String name;
  final ColorScheme colorScheme;

  /// Las pantallas son transparentes y dejan ver un fondo (imagen o degradado).
  final bool transparent;

  /// Cómo se dibuja ese fondo (solo si el tema es transparente).
  final ThemeBackground? background;

  /// Si se indican, al elegir este tema se aplican también esta fuente
  /// y este estilo de barra de progreso (el usuario puede cambiarlos después).
  final String? fontId;
  final String? progressStyleId;

  /// Botones y etiquetas con esquinas rectas (estética más dura).
  final bool sharpCorners;

  const AppThemeSpec({
    required this.id,
    required this.name,
    required this.colorScheme,
    this.transparent = false,
    this.background,
    this.fontId,
    this.progressStyleId,
    this.sharpCorners = false,
  });

  ThemeData build(AppFont font) {
    var scheme = colorScheme;
    if (transparent) {
      // El fondo de las pantallas y de la barra superior sale del color
      // "surface": al hacerlo transparente, se ve lo que haya detrás.
      scheme = scheme.copyWith(
        surface: Colors.transparent,
        surfaceTint: Colors.transparent,
      );
    }

    var theme = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: transparent ? Colors.transparent : null,
    );
    theme = theme.copyWith(textTheme: font.apply(theme.textTheme));

    if (sharpCorners) {
      theme = theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: const RoundedRectangleBorder()),
        ),
        chipTheme:
            theme.chipTheme.copyWith(shape: const RoundedRectangleBorder()),
      );
    }
    return theme;
  }
}

class AppThemes {
  static const defaultId = 'light';

  // Para agregar una estética nueva, suma una entrada aquí.
  static final List<AppThemeSpec> all = [
    AppThemeSpec(
      id: 'light',
      name: 'Claro',
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    ),
    AppThemeSpec(
      id: 'dark',
      name: 'Oscuro',
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
    ),
    AppThemeSpec(
      id: 'transparent',
      name: 'Transparente',
      transparent: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
    ),
    AppThemeSpec(
      id: 'grunge',
      name: 'Grunge',
      fontId: 'special_elite',
      progressStyleId: 'thick',
      sharpCorners: true,
      transparent: true,
      background: const ThemeBackground(
        // asset: 'assets/backgrounds/grunge.png', // imagen por defecto (opcional)
        gradient: [Color(0xFF0F0D0B), Color(0xFF3A2A1E)],
        vignette: 0.65,
        pattern: BackgroundPattern.grain,
        patternColor: Color(0xFFDDD5C5),
        patternOpacity: 0.10,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8A4B2A),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF1C1A17),
        onSurface: const Color(0xFFDDD5C5),
        primary: const Color(0xFFC0643C),
        onPrimary: const Color(0xFF1C1A17),
        secondary: const Color(0xFF8E9150),
        onSecondary: const Color(0xFF1C1A17),
      ),
    ),
    AppThemeSpec(
      id: 'emo',
      name: 'Emo',
      fontId: 'permanent_marker',
      progressStyleId: 'classic',
      transparent: true,
      background: const ThemeBackground(
        // asset: 'assets/backgrounds/emo.png', // imagen por defecto (opcional)
        gradient: [Color(0xFF05030A), Color(0xFF3B0A2A)],
        vignette: 0.6,
        pattern: BackgroundPattern.stripes,
        patternColor: Color(0xFFFF2D75),
        patternOpacity: 0.07,
        patternCell: 18,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD81B60),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF0C0A10),
        onSurface: const Color(0xFFEDE7F0),
        primary: const Color(0xFFFF2D75),
        onPrimary: const Color(0xFF1A0010),
        secondary: const Color(0xFF8E24AA),
        onSecondary: const Color(0xFFFFFFFF),
      ),
    ),
    AppThemeSpec(
      id: 'scene',
      name: 'Scene',
      fontId: 'pacifico',
      progressStyleId: 'rainbow',
      transparent: true,
      background: const ThemeBackground(
        asset: 'assets/backgrounds/scene.png',
        vignette: 0.55,
        pattern: BackgroundPattern.checker,
        patternOpacity: 0.06,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF2BD6),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF14001F),
        onSurface: const Color(0xFFFFFFFF),
        primary: const Color(0xFFFF4DDE),
        onPrimary: const Color(0xFF2A0033),
        secondary: const Color(0xFF00E5FF),
        onSecondary: const Color(0xFF00363D),
        tertiary: const Color(0xFFC6FF00),
        onTertiary: const Color(0xFF263300),
      ),
    ),
  ];

  static AppThemeSpec byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}