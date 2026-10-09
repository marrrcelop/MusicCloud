import 'dart:async';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

enum AppErrorType {
  noInternet,
  sessionExpired,
  driveBusy,
  fileNotFound,
  playback,
  unknown,
}

/// Drive respondió con un código de error HTTP (401, 404, 500...).
class DriveException implements Exception {
  final int statusCode;
  const DriveException(this.statusCode);

  @override
  String toString() => 'DriveException($statusCode)';
}

/// No hay sesión de Google, o el permiso ya no es válido.
class SessionException implements Exception {
  const SessionException();

  @override
  String toString() => 'SessionException';
}

/// Un error ya traducido a algo que el usuario entiende.
class AppError {
  final AppErrorType type;
  final String message;

  /// Texto técnico del error original, para poder diagnosticar.
  final String? detail;

  const AppError(this.type, this.message, {this.detail});

  static const offline = AppError(
    AppErrorType.noInternet,
    'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.',
  );

  static const _slow = AppError(
    AppErrorType.driveBusy,
    'La conexión con Drive está lenta o se cortó. Inténtalo de nuevo.',
  );

  bool get needsLogin => type == AppErrorType.sessionExpired;

  /// Convierte cualquier excepción en un AppError con mensaje claro.
  factory AppError.from(Object error) {
    if (error is AppError) return error;
    final base = _classify(error);
    var text = error.toString();
    if (text.length > 300) text = '${text.substring(0, 300)}...';
    return AppError(base.type, base.message, detail: text);
  }

  static AppError _classify(Object error) {
    if (error is SocketException) return offline;

    if (error is TimeoutException) return _slow;

    if (error is http.ClientException) {
      final text = error.message;
      if (text.contains('Failed host lookup') ||
          text.contains('Network is unreachable')) {
        return offline;
      }
      return _slow;
    }

    if (error is SessionException) {
      return const AppError(
        AppErrorType.sessionExpired,
        'Tu sesión de Google caducó. Inicia sesión de nuevo.',
      );
    }

    if (error is GoogleSignInException) {
      return const AppError(
        AppErrorType.sessionExpired,
        'No se pudo iniciar sesión con Google. Inténtalo de nuevo.',
      );
    }

    if (error is DriveException) {
      final code = error.statusCode;
      if (code == 401 || code == 403) {
        return const AppError(
          AppErrorType.sessionExpired,
          'No hay permiso para leer tu Drive. Inicia sesión de nuevo.',
        );
      }
      if (code == 404) {
        return const AppError(
          AppErrorType.fileNotFound,
          'No se encontró el archivo en Drive. Puede haber sido movido o eliminado.',
        );
      }
      if (code == 429 || code >= 500) {
        return const AppError(
          AppErrorType.driveBusy,
          'Drive no responde en este momento. Inténtalo en unos minutos.',
        );
      }
    }

    if (error is PlayerException || error is PlayerInterruptedException) {
      return const AppError(
        AppErrorType.playback,
        'No se pudo reproducir esta canción.',
      );
    }

    return const AppError(
      AppErrorType.unknown,
      'Ocurrió un error inesperado. Inténtalo de nuevo.',
    );
  }
}