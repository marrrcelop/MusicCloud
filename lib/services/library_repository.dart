import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/library.dart';
import 'app_error.dart';
import 'auth_service.dart';
import 'drive_service.dart';
import 'library_cache.dart';

enum RefreshStatus {
  /// Todo salió bien.
  ok,

  /// La biblioteca cargó, pero faltaron portadas o datos.
  incomplete,

  /// No se pudo actualizar.
  failed,

  /// Ya había una actualización en curso; no se hizo nada.
  skipped,
}

class RefreshResult {
  final RefreshStatus status;
  final AppError? error;

  const RefreshResult(this.status, [this.error]);
}

/// Único punto de acceso a la biblioteca de música.
///
/// Las pantallas solo piden "dame la biblioteca" ([library]) y "actualiza"
/// ([refresh]); no saben si los datos vienen de Drive o de lo guardado en el
/// teléfono. Si algún día se cambia el almacenamiento (por ejemplo, a una base
/// de datos), el cambio se hace aquí y en [LibraryCache], no en las pantallas.
class LibraryRepository extends ChangeNotifier {
  final AuthService _auth;
  final DriveService _drive;
  final LibraryCache _cache;
  final bool Function() _isOnline;

  LibraryRepository({
    required AuthService auth,
    required bool Function() isOnline,
    DriveService? drive,
    LibraryCache? cache,
  })  : _auth = auth,
        _isOnline = isOnline,
        _drive = drive ?? DriveService(),
        _cache = cache ?? LibraryCache();

  Library? _library;
  Map<String, CachedMeta> _metas = {};
  bool _loading = false;
  bool _upToDate = false;
  AppError? _error;
  bool _disposed = false;

  /// La biblioteca que hay ahora (guardada o recién descargada), o null.
  Library? get library => _library;

  bool get hasSongs => _library?.songs.isNotEmpty ?? false;

  /// True mientras se actualiza desde Drive.
  bool get loading => _loading;

  /// Error de la última actualización (null si salió bien).
  AppError? get error => _error;

  /// True si la última actualización terminó bien y completa.
  bool get upToDate => _upToDate;

  /// Carga lo guardado en el teléfono. Es casi instantáneo y no usa internet.
  Future<void> loadSaved() async {
    final cached = await _cache.load();
    if (cached == null || hasSongs) return;
    _library = cached.library;
    _metas = cached.metas;
    notifyListeners();
  }

  /// Actualiza la biblioteca desde Drive.
  ///
  /// Nunca lanza errores: los deja en [error] y en el resultado. Si ya había
  /// una biblioteca, se conserva aunque la actualización falle.
  Future<RefreshResult> refresh({bool interactive = false}) async {
    if (_loading) return const RefreshResult(RefreshStatus.skipped);

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final headers = await _auth.getHeaders(interactive: interactive);
      if (headers == null) throw const SessionException();

      final result = await _drive.fetchLibrary(
        _auth.getHeaders,
        cachedMetas: _metas,
        // Si todavía no hay nada que mostrar, enseñamos las canciones en cuanto
        // llegan, aunque falten portadas y datos.
        onBasic: (basic) {
          if (!hasSongs) {
            _library = basic;
            notifyListeners();
          }
        },
      );

      _library = result.library;
      _metas = result.metas;

      if (result.library.incomplete) {
        _upToDate = false;
        return const RefreshResult(RefreshStatus.incomplete);
      }

      _upToDate = true;
      // Solo guardamos una biblioteca completa, para no empeorar la guardada.
      unawaited(_cache.save(result.library, result.metas));
      return const RefreshResult(RefreshStatus.ok);
    } catch (e) {
      debugPrint('Error cargando la biblioteca: $e');
      // Sin internet casi cualquier fallo es de conexión, así que lo decimos así.
      final error = _isOnline() ? AppError.from(e) : AppError.offline;
      _error = error;
      _upToDate = false;
      return RefreshResult(RefreshStatus.failed, error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Olvida todo (al cerrar sesión): la biblioteca y lo guardado en el teléfono.
  Future<void> clear() async {
    await _cache.clear();
    _library = null;
    _metas = {};
    _error = null;
    _upToDate = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    // Una actualización puede terminar después de cerrar la pantalla.
    if (!_disposed) super.notifyListeners();
  }
}