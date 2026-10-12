import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/song.dart';
import 'audio_handler.dart';
import 'drive_audio_source.dart';

class PlayerService {
  final AudioPlayer _player;
  final AndroidLoudnessEnhancer _loudness;
  final MusicAudioHandler _handler;

  List<Song> _queue = [];
  HeadersProvider? _getDriveHeaders;

  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final StreamController<Song?> _currentController =
      StreamController<Song?>.broadcast();
  Song? _current;

  PlayerService._(this._player, this._loudness, this._handler) {
    _handler.onClose = close;

    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Error del reproductor: $error');
        _errors.add(error);
      },
    );

    _player.currentIndexStream.listen((index) {
      _setCurrent(
        index == null || index >= _queue.length ? null : _queue[index],
      );
    });
  }

  /// Crea el reproductor y lo conecta con la notificación. Se llama una vez, al iniciar la app.
  static Future<PlayerService> create() async {
    final loudness = AndroidLoudnessEnhancer();
    final player = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [loudness]),
    );
    final handler = await AudioService.init(
      builder: () => MusicAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.musiccloud.channel.audio',
        androidNotificationChannelName: 'Reproducción de música',
        androidNotificationOngoing: true,
      ),
    );
    return PlayerService._(player, loudness, handler);
  }

  void _setCurrent(Song? song) {
    if (song == _current) return;
    _current = song;
    _currentController.add(song);
  }

  Stream<Object> get errorStream => _errors.stream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<bool> get shuffleStream => _player.shuffleModeEnabledStream;
  Stream<double> get boostStream => _loudness.targetGainStream;

  /// La canción que suena ahora mismo (o null si no hay ninguna).
  Song? get currentSong => _current;

  /// Canción actual. Entrega primero el valor de ahora y luego los cambios.
  Stream<Song?> get currentSongStream async* {
    yield _current;
    yield* _currentController.stream;
  }

  Future<void> playQueue(
    List<Song> songs,
    int startIndex, {
    required HeadersProvider getDriveHeaders,
  }) async {
    _queue = songs;
    _getDriveHeaders = getDriveHeaders;
    _handler.setItems([for (final s in songs) _mediaItem(s)]);
    try {
      await _player.setAudioSources(
        songs.map((s) => _toSource(s, getDriveHeaders)).toList(),
        initialIndex: startIndex,
      );
    } on PlayerInterruptedException {
      return; // el usuario eligió otra canción antes de terminar de cargar
    }
    _player.play();
  }

  /// Vuelve a cargar la cola en la misma canción y posición (tras un corte).
  Future<void> retryCurrent() async {
    final getHeaders = _getDriveHeaders;
    if (_queue.isEmpty || getHeaders == null) return;

    final index = _player.currentIndex ?? 0;
    final position = _player.position;
    try {
      await _player.setAudioSources(
        _queue.map((s) => _toSource(s, getHeaders)).toList(),
        initialIndex: index,
        initialPosition: position,
      );
    } on PlayerInterruptedException {
      return;
    }
    _player.play();
  }

  /// Detiene la música, vacía la cola y quita la notificación.
  Future<void> close() async {
    _queue = [];
    _getDriveHeaders = null;
    _handler.setItems(const []);
    _setCurrent(null);
    try {
      await _player.pause();
      await _player.stop();
    } catch (e) {
      debugPrint('Error al detener el reproductor: $e');
    }
    await _handler.idle();
  }

  MediaItem _mediaItem(Song song) => MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.albumName,
      );

  AudioSource _toSource(Song song, HeadersProvider getDriveHeaders) {
    switch (song.source) {
      case SongSource.drive:
        return DriveAudioSource(
          fileId: song.path,
          getHeaders: getDriveHeaders,
        );
      case SongSource.local:
        return AudioSource.uri(Uri.parse(song.path));
    }
  }

  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();

  Future<void> setShuffle(bool enabled) async {
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
  }

  Future<void> setBoost(double gain) async {
    await _loudness.setTargetGain(gain);
    await _loudness.setEnabled(gain > 0);
  }

  Future<void> pause() => _player.pause();
  void resume() => _player.play();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> dispose() async {
    await _errors.close();
    await _currentController.close();
    await _player.dispose();
  }
}