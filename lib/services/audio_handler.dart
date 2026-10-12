import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  static const closeActionName = 'close';
  static const _restartThreshold = Duration(seconds: 3);

  static final _closeControl = MediaControl.custom(
    androidIcon: 'drawable/ic_close',
    label: 'Cerrar',
    name: closeActionName,
  );

  final AudioPlayer player;
  List<MediaItem> _items = [];

  /// Lo asigna PlayerService: se llama cuando la notificación pide cerrar.
  Future<void> Function()? onClose;

  MusicAudioHandler(this.player) {
    player.playbackEventStream.listen(
      (event) => playbackState.add(_stateFrom(event)),
      onError: (Object error, StackTrace stack) {}, // PlayerService ya los maneja
    );
    player.playingStream.listen(
      (_) => playbackState.add(_stateFrom(player.playbackEvent)),
    );
    player.currentIndexStream.listen(_onIndexChanged);
    player.durationStream.listen(_onDuration);
  }

  /// Canciones de la cola actual, con los datos que muestra la notificación.
  void setItems(List<MediaItem> items) {
    _items = [...items];
    queue.add(_items);
    if (items.isEmpty) mediaItem.add(null);
  }

  void _onIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _items.length) return;
    mediaItem.add(_items[index]);
  }

  /// La duración permite que la notificación muestre la barra de progreso.
  void _onDuration(Duration? duration) {
    final index = player.currentIndex;
    if (duration == null || index == null) return;
    if (index < 0 || index >= _items.length) return;
    final item = _items[index].copyWith(duration: duration);
    _items[index] = item;
    mediaItem.add(item);
  }

  PlaybackState _stateFrom(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _closeControl,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  /// Pasados 3 segundos reinicia la canción; antes de eso, pasa a la anterior.
  /// Vale para la notificación, la pantalla de bloqueo y los auriculares.
  @override
  Future<void> skipToPrevious() async {
    final pastStart = player.position > _restartThreshold;
    if (pastStart || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  /// Se llama al deslizar la notificación o al tocar el botón de cerrar.
  @override
  Future<void> stop() async {
    final close = onClose;
    if (close != null) {
      await close();
    } else {
      await player.stop();
      await super.stop();
    }
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == closeActionName) {
      await stop();
      return null;
    }
    return super.customAction(name, extras);
  }

  /// Marca el reproductor como inactivo: Android quita la notificación.
  Future<void> idle() => super.stop();
}