import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Pide el permiso de notificaciones. En Android 12 o anterior ya viene concedido.
  Future<PermissionStatus> requestNotifications() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return status;
    return Permission.notification.request();
  }

  /// Abre la pantalla de ajustes de la app en el sistema.
  Future<bool> openSettings() => openAppSettings();
}