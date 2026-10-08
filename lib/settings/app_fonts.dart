import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Una fuente que el usuario puede elegir.
class AppFont {
  final String id;
  final String name;

  /// Nombre exacto en Google Fonts. Si es null, se usa la fuente por defecto.
  final String? family;

  const AppFont(this.id, this.name, [this.family]);

    TextTheme apply(TextTheme base) {
    final name = family;
    if (name == null) return base;
    return base.apply(fontFamily: GoogleFonts.getFont(name).fontFamily);
  }

  /// Estilo para mostrar el nombre de la fuente escrito con ella misma.
  TextStyle? previewStyle() =>
      family == null ? null : GoogleFonts.getFont(family!);
}

class AppFonts {
  static const defaultId = 'default';

  // Para agregar otra fuente, suma una línea aquí.
  static const List<AppFont> all = [
    AppFont('default', 'Predeterminada'),
    AppFont('poppins', 'Poppins', 'Poppins'),
    AppFont('lora', 'Lora', 'Lora'),
    AppFont('pacifico', 'Pacifico', 'Pacifico'),
    AppFont('special_elite', 'Special Elite', 'Special Elite'),
    AppFont('permanent_marker', 'Permanent Marker', 'Permanent Marker'),
    AppFont('unifraktur', 'UnifrakturCook', 'UnifrakturCook'),
    AppFont('press_start', 'Press Start 2P', 'Press Start 2P'),
  ];

  static AppFont byId(String id) =>
      all.firstWhere((f) => f.id == id, orElse: () => all.first);
}