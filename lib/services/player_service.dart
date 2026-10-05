import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'drive_audio_source.dart';

class PlayerService {
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_loudness]),
  );

  List<Song> _queue = [];
  HeadersProvider? _getDriveHeaders;

  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final StreamController<Song?> _currentController =
      StreamController<Song?>.broadcast();
  Song? _current;

  PlayerService() {
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
    _setCurrent(null);
    try {
      await _player.pause();
      await _player.stop();
    } catch (e) {
      debugPrint('Error al detener el reproductor: $e');
    }
  }

  AudioSource _toSource(Song song, HeadersProvider getDriveHeaders) {
    final tag = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      artUri: song.coverUri == null ? null : Uri.parse(song.coverUri!),
    );

    switch (song.source) {
      case SongSource.drive:
        return DriveAudioSource(
          fileId: song.path,
          getHeaders: getDriveHeaders,
          tag: tag,
        );
      case SongSource.local:
        return AudioSource.uri(Uri.parse(song.path), tag: tag);
    }
  }

  Future<void> next() => _player.seekToNext();
  Future<void> previous() => _player.seekToPrevious();

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