import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/album.dart';
import '../models/album_meta_editor.dart';
import '../models/library.dart';
import '../models/song.dart';
import 'app_error.dart';
import 'auth_service.dart';
import 'drive_service.dart';
import 'image_tools.dart';
import 'library_cache.dart';
import 'upload_tools.dart';

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

  /// Avisos de partes que no se pudieron completar (lo principal sí salió).
  final List<String> warnings;

  const RefreshResult(this.status, {this.error, this.warnings = const []});
}

/// Único punto de acceso a la biblioteca de música.
///
/// Las pantallas solo piden "dame la biblioteca" ([library]) y "actualiza"
/// ([refresh]); no saben si los datos vienen de Drive o de lo guardado en el
/// teléfono. También concentra las ediciones, movimientos, subidas y borrados.
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
      return RefreshResult(RefreshStatus.failed, error: error);
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

  // ---------- Edición, creación, movimientos, subidas y borrado ----------
  //
  // Estas operaciones SÍ lanzan errores (la pantalla los muestra). Al terminar
  // vuelven a leer Drive para mostrar el estado real.

  /// Guarda los datos de una canción en el album.json de su carpeta.
  Future<RefreshResult> saveSong(
    Song song, {
    required String title,
    required String artist,
    required String genre,
    required int? year,
  }) async {
    final albumId = song.albumId;
    final fileName = song.fileName;
    if (albumId == null || fileName == null) {
      throw StateError('La canción no está dentro de una carpeta.');
    }

    // Solo escribimos lo que cambió. Vaciar un campo borra el dato propio de la
    // canción y vuelve a valer el del álbum (o el nombre del archivo).
    final fields = <String, Object?>{};
    if (title.trim() != song.title) fields['title'] = _orNull(title);
    final currentArtist = song.artist == Song.unknownArtist ? '' : song.artist;
    if (artist.trim() != currentArtist) fields['artist'] = _orNull(artist);
    if (genre.trim() != (song.genre ?? '')) fields['genre'] = _orNull(genre);
    if (year != song.year) fields['year'] = year;
    if (fields.isEmpty) return const RefreshResult(RefreshStatus.ok);

    Object? failure;
    try {
      await _updateAlbumJson(albumId, songFileName: fileName, song: fields);
    } catch (e) {
      failure = e;
    }
    return _finishWrite(failure);
  }

  /// Guarda los datos de un álbum: nombre, artista, año, género y portada.
  Future<RefreshResult> saveAlbum(
    Album album, {
    required String name,
    required String artist,
    required String genre,
    required int? year,
    PreparedImage? cover,
  }) async {
    Object? failure;
    try {
      // 1) Datos (primero, porque es lo que más puede fallar sin haber cambiado nada).
      final fields = <String, Object?>{};
      if (artist.trim() != (album.artist ?? '')) {
        fields['artist'] = _orNull(artist);
      }
      if (genre.trim() != (album.genre ?? '')) {
        fields['genre'] = _orNull(genre);
      }
      if (year != album.year) fields['year'] = year;
      if (fields.isNotEmpty) await _updateAlbumJson(album.id, album: fields);

      // 2) Nombre (el nombre de la carpeta).
      final newName = name.trim();
      if (newName.isNotEmpty && newName != album.name) {
        await _drive.renameFile(_auth.getHeaders, album.id, newName);
      }

      // 3) Portada: se sube la nueva y recién entonces se retira la anterior.
      if (cover != null) {
        await _drive.createFile(
          _auth.getHeaders,
          name: 'cover.${cover.extension}',
          parentId: album.id,
          mimeType: cover.mimeType,
          bytes: cover.bytes,
        );
        final oldId = _coverFileId(album.coverUri);
        if (oldId != null) {
          try {
            await _drive.trashFile(_auth.getHeaders, oldId);
          } catch (e) {
            debugPrint('No se pudo retirar la portada anterior: $e');
          }
        }
      }
    } catch (e) {
      failure = e;
    }
    return _finishWrite(failure);
  }

  /// Crea un álbum nuevo (una carpeta en la raíz de Drive) y devuelve su id.
  Future<String> createAlbum(String name) async {
    String? id;
    Object? failure;
    try {
      final folderId = await _drive.createFolder(
        _auth.getHeaders,
        name: name.trim(),
      );
      id = folderId;
      try {
        // El album.json vacío hace que la carpeta cuente como álbum aunque
        // todavía no tenga canciones.
        await _drive.createFile(
          _auth.getHeaders,
          name: 'album.json',
          parentId: folderId,
          mimeType: 'application/json',
          bytes: Uint8List.fromList(utf8.encode('{}')),
        );
      } catch (e) {
        // No dejamos una carpeta invisible: la retiramos.
        try {
          await _drive.trashFile(_auth.getHeaders, folderId);
        } catch (_) {}
        id = null;
        rethrow;
      }
    } catch (e) {
      failure = e;
    }
    await _finishWrite(failure); // si hubo un fallo, lo lanza aquí
    return id!;
  }

  /// Mueve una canción a otro álbum, llevándose su imagen propia y sus datos.
  Future<RefreshResult> moveSong(Song song, Album destination) async {
    final fileName = song.fileName;
    final sourceId = song.albumId;
    if (fileName == null) {
      throw StateError('La canción no tiene nombre de archivo.');
    }
    if (sourceId == destination.id) {
      throw StateError('La canción ya está en ese álbum.');
    }

    // ¿Tiene una imagen propia (distinta de la portada del álbum)?
    Album? source;
    for (final a in _library?.albums ?? const <Album>[]) {
      if (a.id == sourceId) source = a;
    }
    final ownCoverId =
        (song.coverUri != null && song.coverUri != source?.coverUri)
            ? _coverFileId(song.coverUri)
            : null;

    final warnings = <String>[];
    Object? failure;
    try {
      // 1) Leemos los datos propios de la canción (sin modificar nada todavía).
      Map<String, dynamic>? entry;
      String? sourceText;
      final sourceJsonId = sourceId == null ? null : _metaFileIdFor(sourceId);
      if (sourceJsonId != null) {
        try {
          final raw = await _drive.downloadBytes(_auth.getHeaders, sourceJsonId);
          final taken = AlbumMetaEditor.takeSong(
            utf8.decode(raw, allowMalformed: true),
            fileName,
          );
          entry = taken.entry;
          if (entry != null) sourceText = taken.text;
        } catch (e) {
          debugPrint('No se pudieron leer los datos de la canción: $e');
          warnings.add('No se pudieron leer los datos de la canción.');
        }
      }

      // 2) Mover el archivo: lo único imprescindible.
      await _drive.moveFile(
        _auth.getHeaders,
        song.id,
        toParent: destination.id,
        fromParent: sourceId,
      );

      // 3) El resto es "lo mejor posible": la canción ya está movida.
      if (ownCoverId != null) {
        try {
          await _drive.moveFile(
            _auth.getHeaders,
            ownCoverId,
            toParent: destination.id,
            fromParent: sourceId,
          );
        } catch (e) {
          debugPrint('No se pudo mover la imagen de la canción: $e');
          warnings.add('No se pudo mover la imagen propia de la canción.');
        }
      }
      if (entry != null) {
        try {
          await _updateAlbumJson(
            destination.id,
            songFileName: fileName,
            song: entry,
          );
          if (sourceJsonId != null && sourceText != null) {
            await _drive.updateContent(
              _auth.getHeaders,
              sourceJsonId,
              Uint8List.fromList(utf8.encode(sourceText)),
              'application/json',
            );
          }
        } catch (e) {
          debugPrint('No se pudieron mover los datos de la canción: $e');
          warnings.add(
            'No se pudieron mover los datos de la canción '
            '(quedaron en el álbum de origen).',
          );
        }
      }
    } catch (e) {
      failure = e;
    }

    final refreshed = await _finishWrite(failure);
    return RefreshResult(
      refreshed.status,
      error: refreshed.error,
      warnings: warnings,
    );
  }

  /// Sube canciones a un álbum, una por una. No lanza errores por archivo:
  /// los reporta en el resultado.
  Future<UploadReport> uploadSongs(
    Album album,
    List<UploadItem> items, {
    void Function(int index, int sent, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final existing = <String>{
      for (final s in _library?.songsOf(album.id) ?? const <Song>[])
        if (s.fileName != null) s.fileName!.toLowerCase(),
    };

    var uploaded = 0;
    var cancelled = false;
    final skipped = <String>[];
    final failed = <String>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      if (existing.contains(item.name.toLowerCase())) {
        skipped.add(item.name);
        continue;
      }

      onProgress?.call(i, 0, item.size);
      try {
        await _drive.uploadFile(
          _auth.getHeaders,
          path: item.path,
          name: item.name,
          parentId: album.id,
          mimeType: item.mimeType,
          onProgress: (sent, total) => onProgress?.call(i, sent, total),
          isCancelled: isCancelled,
        );
        uploaded++;
        existing.add(item.name.toLowerCase());
      } on UploadCancelled {
        cancelled = true;
        break;
      } catch (e) {
        debugPrint('No se pudo subir ${item.name}: $e');
        final reason = _isOnline() ? AppError.from(e).message : AppError.offline.message;
        failed.add('${item.name}: $reason');
        // Sin sesión o sin permiso, el resto tampoco se podrá subir.
        if (e is SessionException ||
            (e is DriveException &&
                (e.statusCode == 401 || e.statusCode == 403))) {
          break;
        }
      }
    }

    // Se actualiza la biblioteca aunque algo haya fallado: pudo subirse parte.
    if (uploaded > 0) await _finishWrite(null);

    return UploadReport(
      uploaded: uploaded,
      skipped: skipped,
      failed: failed,
      cancelled: cancelled,
    );
  }

  /// Mueve una canción a la papelera de Drive.
  Future<RefreshResult> trashSong(Song song) async {
    Object? failure;
    try {
      await _drive.trashFile(_auth.getHeaders, song.id);
    } catch (e) {
      failure = e;
    }
    return _finishWrite(failure);
  }

  /// Mueve una carpeta (álbum) completa a la papelera de Drive.
  Future<RefreshResult> trashAlbum(Album album) async {
    Object? failure;
    try {
      await _drive.trashFile(_auth.getHeaders, album.id);
    } catch (e) {
      failure = e;
    }
    return _finishWrite(failure);
  }

  /// Vuelve a leer Drive; si algo falló antes, lanza el error después de actualizar.
  Future<RefreshResult> _finishWrite(Object? failure) async {
    // Si justo se está actualizando, esperamos a que termine.
    for (var i = 0; i < 50 && _loading; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final result = await refresh();
    if (failure != null) throw failure;
    return result;
  }

  /// Lee el album.json de una carpeta, le aplica los cambios y lo guarda.
  /// Si no existe, lo crea. Si el actual está mal escrito, no toca nada.
  Future<void> _updateAlbumJson(
    String albumId, {
    Map<String, Object?> album = const {},
    String? songFileName,
    Map<String, Object?> song = const {},
  }) async {
    final fileId = _metaFileIdFor(albumId);
    String? current;
    var exists = false;

    if (fileId != null) {
      try {
        // Se descarga la versión actual (no la guardada), por si cambió en Drive.
        final raw = await _drive.downloadBytes(_auth.getHeaders, fileId);
        current = utf8.decode(raw, allowMalformed: true);
        exists = true;
      } on DriveException catch (e) {
        if (e.statusCode != 404) rethrow; // si ya no existe, se crea uno nuevo
      }
    }

    final text = AlbumMetaEditor.apply(
      current,
      album: album,
      songFileName: songFileName,
      song: song,
    );
    final bytes = Uint8List.fromList(utf8.encode(text));

    if (exists && fileId != null) {
      await _drive.updateContent(
        _auth.getHeaders,
        fileId,
        bytes,
        'application/json',
      );
    } else {
      await _drive.createFile(
        _auth.getHeaders,
        name: 'album.json',
        parentId: albumId,
        mimeType: 'application/json',
        bytes: bytes,
      );
    }
  }

  /// Id del album.json de una carpeta, si se conoce.
  String? _metaFileIdFor(String albumId) {
    for (final entry in _metas.entries) {
      if (entry.value.parent == albumId) return entry.key;
    }
    return null;
  }

  /// Id del archivo de una portada ("drive:ID:VERSIÓN").
  String? _coverFileId(String? uri) {
    if (uri == null || !uri.startsWith('drive:')) return null;
    final parts = uri.split(':');
    return parts.length >= 3 ? parts[1] : null;
  }

  String? _orNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
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