import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_fonts.dart';
import 'app_themes.dart';
import 'progress_styles.dart';

/// Guarda los ajustes de personalización y avisa a la app cuando cambian.
class SettingsController extends ChangeNotifier {
  static const _kTheme = 'theme_id';
  static const _kFont = 'font_id';
  static const _kProgress = 'progress_style_id';
  static const _kMascotPath = 'mascot_path';
  static const _kMascotEnabled = 'mascot_enabled';
  static const _kMascotSize = 'mascot_size';
  static const _kMascotDx = 'mascot_dx';
  static const _kMascotDy = 'mascot_dy';
  static const _kSpritePath = 'sprite_path';
  static const _kBackgroundPath = 'background_path';
  static const _kBackgroundDim = 'background_dim';

  /// Posición inicial de la mascota (0 a 1 en cada eje): abajo a la derecha.
  static const defaultMascotDx = 0.97;
  static const defaultMascotDy = 0.85;

  final SharedPreferences _prefs;

  late String _themeId;
  late String _fontId;
  late String _progressStyleId;
  String? _mascotPath;
  late bool _mascotEnabled;
  late double _mascotSize;
  late double _mascotDx;
  late double _mascotDy;
  String? _spritePath;
  String? _backgroundPath;
  late double _backgroundDim;

  SettingsController._(this._prefs) {
    _themeId = _prefs.getString(_kTheme) ?? AppThemes.defaultId;
    _fontId = _prefs.getString(_kFont) ?? AppFonts.defaultId;
    _progressStyleId = _prefs.getString(_kProgress) ?? ProgressStyles.defaultId;
    _mascotPath = _prefs.getString(_kMascotPath);
    _mascotEnabled = _prefs.getBool(_kMascotEnabled) ?? false;
    _mascotSize = _prefs.getDouble(_kMascotSize) ?? 96;
    _mascotDx = _prefs.getDouble(_kMascotDx) ?? defaultMascotDx;
    _mascotDy = _prefs.getDouble(_kMascotDy) ?? defaultMascotDy;
    _spritePath = _prefs.getString(_kSpritePath);
    _backgroundPath = _prefs.getString(_kBackgroundPath);
    _backgroundDim = _prefs.getDouble(_kBackgroundDim) ?? 0.45;
  }

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsController._(prefs);
  }

  String get themeId => _themeId;
  String get fontId => _fontId;
  String get progressStyleId => _progressStyleId;
  String? get mascotPath => _mascotPath;
  bool get mascotEnabled => _mascotEnabled;
  double get mascotSize => _mascotSize;
  double get mascotDx => _mascotDx;
  double get mascotDy => _mascotDy;
  String? get spritePath => _spritePath;
  String? get backgroundPath => _backgroundPath;
  double get backgroundDim => _backgroundDim;

  // ---------- Tema, fuente y barra ----------

  /// Cambia el tema. Si el tema trae fuente o barra sugeridas, las aplica también.
  Future<void> setTheme(String id) async {
    final spec = AppThemes.byId(id);
    _themeId = spec.id;
    await _prefs.setString(_kTheme, spec.id);

    final fontId = spec.fontId;
    if (fontId != null) {
      _fontId = fontId;
      await _prefs.setString(_kFont, fontId);
    }
    final barId = spec.progressStyleId;
    if (barId != null) {
      _progressStyleId = barId;
      await _prefs.setString(_kProgress, barId);
    }
    notifyListeners();
  }

  Future<void> setFont(String id) async {
    _fontId = id;
    notifyListeners();
    await _prefs.setString(_kFont, id);
  }

  Future<void> setProgressStyle(String id) async {
    _progressStyleId = id;
    notifyListeners();
    await _prefs.setString(_kProgress, id);
  }

  // ---------- Fondo (temas transparentes) ----------

  Future<bool> pickBackground() async {
    final path = await _importImage('background', _backgroundPath);
    if (path == null) return false;
    _backgroundPath = path;
    notifyListeners();
    await _prefs.setString(_kBackgroundPath, path);
    return true;
  }

  Future<void> clearBackground() async {
    await _deleteFile(_backgroundPath);
    _backgroundPath = null;
    notifyListeners();
    await _prefs.remove(_kBackgroundPath);
  }

  Future<void> setBackgroundDim(double value) async {
    _backgroundDim = value;
    notifyListeners();
    await _prefs.setDouble(_kBackgroundDim, value);
  }

  // ---------- Mascota ----------

  Future<void> setMascotEnabled(bool value) async {
    _mascotEnabled = value;
    notifyListeners();
    await _prefs.setBool(_kMascotEnabled, value);
  }

  Future<void> setMascotSize(double value) async {
    _mascotSize = value;
    notifyListeners();
    await _prefs.setDouble(_kMascotSize, value);
  }

  /// Mueve la mascota mientras se arrastra (no guarda todavía).
  void moveMascot(double dx, double dy) {
    _mascotDx = dx;
    _mascotDy = dy;
    notifyListeners();
  }

  /// Guarda la posición actual (se llama al soltar).
  Future<void> commitMascotPosition() async {
    await _prefs.setDouble(_kMascotDx, _mascotDx);
    await _prefs.setDouble(_kMascotDy, _mascotDy);
  }

  Future<void> resetMascotPosition() async {
    _mascotDx = defaultMascotDx;
    _mascotDy = defaultMascotDy;
    notifyListeners();
    await commitMascotPosition();
  }

  /// Devuelve true si el usuario eligió una imagen (false si canceló).
  Future<bool> pickMascot() async {
    final path = await _importImage('mascot', _mascotPath);
    if (path == null) return false;
    _mascotPath = path;
    _mascotEnabled = true;
    notifyListeners();
    await _prefs.setString(_kMascotPath, path);
    await _prefs.setBool(_kMascotEnabled, true);
    return true;
  }

  Future<void> clearMascot() async {
    await _deleteFile(_mascotPath);
    _mascotPath = null;
    _mascotEnabled = false;
    notifyListeners();
    await _prefs.remove(_kMascotPath);
    await _prefs.setBool(_kMascotEnabled, false);
  }

  // ---------- Imagen de la punta de la barra ----------

  Future<bool> pickSprite() async {
    final path = await _importImage('sprite', _spritePath);
    if (path == null) return false;
    _spritePath = path;
    notifyListeners();
    await _prefs.setString(_kSpritePath, path);
    return true;
  }

  Future<void> clearSprite() async {
    await _deleteFile(_spritePath);
    _spritePath = null;
    notifyListeners();
    await _prefs.remove(_kSpritePath);
  }

  // ---------- Utilidades ----------

  /// Deja elegir una imagen y la copia a la carpeta privada de la app.
  /// Devuelve la nueva ruta, o null si el usuario canceló.
  Future<String?> _importImage(String prefix, String? previousPath) async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return null; // canceló

    final sourcePath = picked.path;
    if (sourcePath == null) return null;

    // Sacamos la extensión (png, gif...) del nombre del archivo.
    final dot = sourcePath.lastIndexOf('.');
    final separator = sourcePath.lastIndexOf(Platform.pathSeparator);
    final ext = dot > separator ? sourcePath.substring(dot + 1) : 'png';

    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = '${dir.path}${Platform.pathSeparator}${prefix}_$stamp.$ext';
    await File(sourcePath).copy(target);

    await _deleteFile(previousPath);
    return target;
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {
      // Si ya no existe, no pasa nada.
    }
  }
}