import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'drive_audio_source.dart';

class PlayerService {
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_loudness]),
  );
  Stream<double> get boostStream => _loudness.targetGainStream;

  Future<void> setBoost(double gain) async {
    await _loudness.setTargetGain(gain);
    await _loudness.setEnabled(gain > 0);
  }
  List<Song> _queue = [];

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<double> get volumeStream => _player.volumeStream;
  Stream<bool> get shuffleStream => _player.shuffleModeEnabledStream;

  Stream<Song?> get currentSongStream =>
      _player.currentIndexStream.map((index) {
        if (index == null || index >= _queue.length) return null;
        return _queue[index];
      });

  Future<void> playQueue(
    List<Song> songs,
    int startIndex, {
    required HeadersProvider getDriveHeaders,
  }) async {
    _queue = songs;
    await _player.setAudioSources(
      songs.map((s) => _toSource(s, getDriveHeaders)).toList(),
      initialIndex: startIndex,
    );
    _player.play();
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

  Future<void> pause() => _player.pause();
  void resume() => _player.play();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  Future<void> dispose() => _player.dispose();
}