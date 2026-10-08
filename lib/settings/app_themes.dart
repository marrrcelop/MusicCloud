import 'package:flutter/material.dart';
import 'app_fonts.dart';

/// Un tema completo que el usuario puede elegir.
class AppThemeSpec {
  final String id;
  final String name;
  final ColorScheme colorScheme;

  const AppThemeSpec({
    required this.id,
    required this.name,
    required this.colorScheme,
  });

  ThemeData build(AppFont font) {
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    return base.copyWith(textTheme: font.apply(base.textTheme));
  }
}

class AppThemes {
  static const defaultId = 'light';

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
    // Aquí irán las estéticas futuras (emo, gótico, grunge...). Ejemplo:
    // AppThemeSpec(
    //   id: 'gotico',
    //   name: 'Gótico',
    //   colorScheme: ColorScheme.fromSeed(
    //     seedColor: Colors.red,
    //     brightness: Brightness.dark,
    //   ),
    // ),
  ];

  static AppThemeSpec byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}