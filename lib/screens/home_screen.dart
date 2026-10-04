import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/auth_service.dart';
import '../services/drive_service.dart';
import '../services/player_service.dart';
import 'widgets/player_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PlayerService _player = PlayerService();
  final AuthService _auth = AuthService();
  final DriveService _drive = DriveService();

  List<Song> _songs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _tryAutoLogin() async {
    try {
      if (await _auth.trySilentSignIn()) {
        await _loadSongs(interactive: false);
      }
    } catch (e) {
      debugPrint('Auto-login falló: $e');
    }
  }

  Future<void> _connect() async {
    try {
      await _auth.signIn();
      await _loadSongs(interactive: true);
    } catch (e) {
      debugPrint('Error de login: $e');
      _showError('No se pudo conectar con Drive');
    }
  }

  Future<void> _loadSongs({required bool interactive}) async {
    setState(() => _loading = true);
    try {
      final headers = await _auth.getHeaders(interactive: interactive);
      if (headers == null) {
        debugPrint('Todavía no hay permiso para leer Drive');
        return;
      }
       final songs = await _drive.fetchSongs(_auth.getHeaders);
      debugPrint('Drive devolvió ${songs.length} archivos de audio');
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      debugPrint('Error cargando canciones: $e');
      _showError('No se pudo cargar la biblioteca');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playFrom(int index) async {
    try {
      await _player.playQueue(_songs, index, getDriveHeaders: _auth.getHeaders);
    } catch (e) {
      debugPrint('Error al reproducir: $e');
      _showError('No se pudo reproducir el audio');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MusicCloud'),
        actions: [
          if (_auth.isSignedIn)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadSongs(interactive: true),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: PlayerBar(player: _player),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64),
            const SizedBox(height: 16),
            Text(_auth.isSignedIn
                ? 'No se encontraron canciones en tu Drive'
                : 'Conecta tu Google Drive para ver tu música'),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: Icon(_auth.isSignedIn ? Icons.refresh : Icons.login),
              label: Text(
                _auth.isSignedIn
                    ? 'Dar acceso / Reintentar'
                    : 'Conectar con Google Drive',
              ),
              onPressed: _auth.isSignedIn
                  ? () => _loadSongs(interactive: true)
                  : _connect,
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Song?>(
      stream: _player.currentSongStream,
      builder: (context, snapshot) {
        final current = snapshot.data;
        return ListView.builder(
          itemCount: _songs.length,
          itemBuilder: (context, index) {
            final song = _songs[index];
            return ListTile(
              leading: const Icon(Icons.cloud),
              title: Text(song.title),
              subtitle: Text(song.artist),
              selected: song == current,
              onTap: () => _playFrom(index),
            );
          },
        );
      },
    );
  }
}