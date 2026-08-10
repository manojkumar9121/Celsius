import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/services/background_audio_service.dart';
import 'package:celsuis/services/widget_service.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';

final audioHandlerProvider = StateProvider<AudioPlayerHandler?>((ref) => null);

final audioPlayerStateProvider = StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>((ref) {
  final notifier = AudioPlayerNotifier();
  ref.listen(audioHandlerProvider, (_, handler) => notifier.setHandler(handler));
  return notifier;
});

final audioPlayerProvider = audioPlayerStateProvider;

class AudioPlayerNotifier extends StateNotifier<AudioPlayerState> with WidgetsBindingObserver {
  AudioPlayerHandler? _handler;
  final WidgetService _widgetService = WidgetService();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  bool _widgetCallbacksSet = false;

  AudioPlayerNotifier() : super(const AudioPlayerState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  void setHandler(AudioPlayerHandler? handler) {
    if (identical(handler, _handler)) return;
    _handler = handler;

    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _mediaItemSub?.cancel();
    _positionSub = null;
    _playerStateSub = null;
    _mediaItemSub = null;

    if (handler == null) return;

    if (!_widgetCallbacksSet) {
      _widgetCallbacksSet = true;
      _widgetService.onPrevious = () => skipToPrevious();
      _widgetService.onPlayPause = () => togglePlayPause();
      _widgetService.onNext = () => skipToNext();
    }

    _positionSub = handler.player.positionStream.listen((pos) {
      try {
        state = state.copyWith(position: pos);
      } catch (e) {
        debugPrint('Position update error: $e');
      }
    }, onError: (e) => debugPrint('Position stream error: $e'));
    _playerStateSub = handler.player.playerStateStream.listen((ps) {
      try {
        final isPlaying = ps.playing && ps.processingState != ProcessingState.completed;
        if (isPlaying != state.isPlaying) {
          state = state.copyWith(isPlaying: isPlaying);
        }
      } catch (e) {
        debugPrint('Player state update error: $e');
      }
    }, onError: (e) => debugPrint('Player state stream error: $e'));
    _mediaItemSub = handler.mediaItem.listen((item) {
      if (item == null) return;
      final song = handler.songs.where((s) => s.id == item.id).firstOrNull;
      if (song == null) return;
      try {
        state = state.copyWith(
          currentSong: song,
          queue: List.of(handler.songs),
          totalDuration: handler.player.duration ?? Duration(milliseconds: song.durationMs),
        );
      } catch (e) {
        debugPrint('Media item update error: $e');
      }
    }, onError: (e) => debugPrint('Media item stream error: $e'));
  }

  Future<void> playSong(SongEntity song, List<SongEntity>? queue) async {
    final resolvedQueue = queue ?? [song];

    state = state.copyWith(
      currentSong: song,
      isPlaying: false,
      queue: resolvedQueue,
      totalDuration: Duration(milliseconds: song.durationMs),
    );

    final handler = _handler;
    if (handler == null) return;
    try {
      await handler.setQueue(resolvedQueue, initialSong: song);
    } catch (e) {
      debugPrint('Failed to set queue: $e');
      state = state.copyWith(isPlaying: false);
      return;
    }

    try {
      state = state.copyWith(
        isPlaying: true,
        totalDuration: handler.player.duration ?? state.totalDuration,
      );
    } catch (e) {
      debugPrint('Play state update error: $e');
    }

    _widgetService.trackSong(song);
    _widgetService.onSongChanged(song, true);
    unawaited(HiveStorage.incrementPlayCount(song.id));
  }

  Future<void> togglePlayPause() async {
    final handler = _handler;
    if (handler == null) return;
    if (handler.isPlaying) {
      await handler.pause();
      state = state.copyWith(isPlaying: false);
      _widgetService.onPlayStateChanged(false);
    } else {
      await handler.play();
      state = state.copyWith(isPlaying: true);
      _widgetService.onPlayStateChanged(true);
    }
  }

  Future<void> play() async {
    final handler = _handler;
    if (handler == null) return;
    await handler.play();
    state = state.copyWith(isPlaying: true);
    _widgetService.onPlayStateChanged(true);
  }

  void pause() {
    final handler = _handler;
    if (handler == null) return;
    handler.pause();
    state = state.copyWith(isPlaying: false);
    _widgetService.onPlayStateChanged(false);
  }

  Future<void> skipToNext() async {
    final handler = _handler;
    if (handler == null) return;
    await handler.skipToNext();
  }

  Future<void> skipToPrevious() async {
    final handler = _handler;
    if (handler == null) return;
    await handler.skipToPrevious();
  }

  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    final handler = _handler;
    if (handler == null) return;
    await handler.skipToQueueItem(index);
  }

  void seek(Duration position) {
    final handler = _handler;
    if (handler == null) return;
    handler.seek(position);
    state = state.copyWith(position: position);
  }

  void setVolume(double volume) {
    final handler = _handler;
    if (handler == null) return;
    handler.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  void setShuffle(bool enabled) {
    final handler = _handler;
    if (handler == null) return;
    handler.setShuffle(enabled);
    state = state.copyWith(isShuffled: enabled);
  }

  void setRepeatMode(AppSettingsRepeatMode mode) {
    final handler = _handler;
    if (handler == null) return;
    AudioServiceRepeatMode audioServiceMode;
    switch (mode) {
      case AppSettingsRepeatMode.off:
        audioServiceMode = AudioServiceRepeatMode.none;
        break;
      case AppSettingsRepeatMode.one:
        audioServiceMode = AudioServiceRepeatMode.one;
        break;
      case AppSettingsRepeatMode.all:
        audioServiceMode = AudioServiceRepeatMode.all;
        break;
    }
    handler.setRepeatMode(audioServiceMode);
    state = state.copyWith(repeatMode: mode);
  }

  void updateCurrentSongFavorite(bool isFavorite) {
    if (state.currentSong != null) {
      state = state.copyWith(
        currentSong: state.currentSong!.copyWith(isFavorite: isFavorite),
      );
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    final handler = _handler;
    if (handler != null) {
      unawaited(handler.reorderQueue(oldIndex, newIndex).catchError((Object e) {
        debugPrint('Queue reorder failed: $e');
      }));
    }
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= state.queue.length) return;

    final songs = List<SongEntity>.from(state.queue);
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);
    state = state.copyWith(queue: songs);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncStateFromHandler();
    }
  }

  Future<void> _syncStateFromHandler() async {
    final handler = _handler;
    if (handler == null) return;
    try {
      final currentPos = handler.player.position;
      final isPlaying = handler.player.playing;
      final totalDur = handler.player.duration ?? state.totalDuration;
      final song = handler.currentSong ?? state.currentSong;
      state = state.copyWith(
        position: currentPos,
        isPlaying: isPlaying,
        totalDuration: totalDur,
        currentSong: song,
      );
    } catch (e) {
      debugPrint('Lifecycle sync error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _mediaItemSub?.cancel();
    super.dispose();
  }
}

class AudioPlayerState {
  final SongEntity? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration totalDuration;
  final List<SongEntity> queue;
  final bool isShuffled;
  final AppSettingsRepeatMode repeatMode;
  final double volume;

  const AudioPlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.totalDuration = Duration.zero,
    this.queue = const [],
    this.isShuffled = false,
    this.repeatMode = AppSettingsRepeatMode.off,
    this.volume = 1.0,
  });

  AudioPlayerState copyWith({
    SongEntity? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? totalDuration,
    List<SongEntity>? queue,
    bool? isShuffled,
    AppSettingsRepeatMode? repeatMode,
    double? volume,
  }) {
    return AudioPlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      totalDuration: totalDuration ?? this.totalDuration,
      queue: queue ?? this.queue,
      isShuffled: isShuffled ?? this.isShuffled,
      repeatMode: repeatMode ?? this.repeatMode,
      volume: volume ?? this.volume,
    );
  }
}
