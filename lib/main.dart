import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';
import 'settings/app_fonts.dart';
import 'settings/app_themes.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_scope.dart';
import 'screens/widgets/app_background.dart';
import 'screens/widgets/mascot_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Errores dentro de widgets de Flutter
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Error de Flutter: ${details.exceptionAsString()}');
  };

  // Errores asíncronos que nadie atrapó
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Error no controlado: $error');
    return true; // true = ya lo manejamos, no cierres la app
  };

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.musiccloud.channel.audio',
    androidNotificationChannelName: 'Reproducción de música',
    androidNotificationOngoing: true,
  );

  final settings = await SettingsController.load();
  runApp(MusicCloudApp(settings: settings));
}

class MusicCloudApp extends StatelessWidget {
  final SettingsController settings;

  const MusicCloudApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'MusicCloud',
            theme: AppThemes.byId(settings.themeId)
                .build(AppFonts.byId(settings.fontId)),
            // Capas: fondo (abajo), pantallas (en medio) y mascota (arriba).
            builder: (context, child) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  const AppBackground(),
                  if (child != null) child,
                  const MascotOverlay(),
                ],
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}