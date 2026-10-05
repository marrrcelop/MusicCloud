import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_screen.dart';

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
  runApp(const MusicCloudApp());
}

class MusicCloudApp extends StatelessWidget {
  const MusicCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MusicCloud',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}