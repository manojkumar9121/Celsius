import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/services/background_audio_service.dart';
import 'package:celsius/services/widget_service.dart';
import 'package:celsius/presentation/providers/settings_provider.dart';

final audioHandlerProvider = StateProvider<AudioPlayerHandler?>((ref) => null);

enum QueueAddResult { added, alreadyQueued, playerUnavailable }

final widgetServiceProvider = Provider<WidgetService>((ref) => WidgetService());

final audioPlayerStateProvider =
    StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>((ref) {
      final notifier = AudioPlayerNotifier(
        widgetService: ref.watch(widgetServiceProvider),
        initialSettings: ref.read(settingsProvider),
      );
      ref.listen(
        audioHandlerProvider,
        (_, handler) => notifier.setHandler(handler),
        fireImmediately: true,
      );
      ref.listen<AppSettings>(settingsProvider, (_, settings) {
        notifier.applyRuntimeSettings(settings);
      });
      return notifier;
    });

final audioPlayerProvider = audioPlayerStateProvider;

class AudioPlayerNotifier extends StateNotifier<AudioPlayerState>
    with WidgetsBindingObserver {
  AudioPlayerHandler? _handler;
  final WidgetService _widgetService;
  AppSettings _runtimeSettings;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  bool _widgetCallbacksSet = false;

  /// Song/queue currently being installed, either because the handler is
  /// initializing or because its FIFO is still loading the requested source.
  SongEntity? _pendingSong;
  List<SongEntity>? _pendingQueue;

  /// Generation counter for the UI queue order. Bumped on every local queue
  /// mutation so stale async completions (e.g. a slow reorder overtaken by a
  /// newer drag or a fresh playSong) never overwrite newer state.
  int _queueVersion = 0;

  AudioPlayerNotifier({
    WidgetService? widgetService,
    AppSettings? initialSettings,
  }) : _widgetService = widgetService ?? WidgetService(),
       _runtimeSettings = initialSettings ?? const AppSettings(),
       super(const AudioPlayerState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Applies a settings snapshot only after SettingsNotifier has committed it
  /// to Hive. This keeps pause behavior and handler configuration independent
  /// of the timing of the settings write queue.
  void applyRuntimeSettings(AppSettings settings) {
    _runtimeSettings = settings;
    _handler?.updateRuntimeSettings(settings);
  }

  void setHandler(AudioPlayerHandler? handler) {
    if (identical(handler, _handler)) return;
    _queueVersion++;
    _handler = handler;

    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _mediaItemSub?.cancel();
    _positionSub = null;
    _playerStateSub = null;
    _mediaItemSub = null;

    if (handler == null) return;

    handler.updateRuntimeSettings(_runtimeSettings);

    if (!_widgetCallbacksSet) {
      _widgetCallbacksSet = true;
      _widgetService.onPrevious = () => skipToPrevious();
      _widgetService.onPlayPause = () => togglePlayPause();
      _widgetService.onNext = () => skipToNext();
      _widgetService.init();
    }

    _positionSub = handler.player.positionStream.listen((pos) {
      if (!mounted || !identical(_handler, handler)) return;
      try {
        state = state.copyWith(position: pos);
      } catch (e) {
        debugPrint('Position update error: $e');
      }
    }, onError: (e) => debugPrint('Position stream error: $e'));
    _playerStateSub = handler.player.playerStateStream.listen((ps) {
      if (!mounted || !identical(_handler, handler)) return;
      try {
        final isPlaying =
            ps.playing && ps.processingState != ProcessingState.completed;
        if (isPlaying != state.isPlaying) {
          state = state.copyWith(isPlaying: isPlaying);
        }
        _widgetService.onPlayStateChanged(isPlaying);
      } catch (e) {
        debugPrint('Player state update error: $e');
      }
    }, onError: (e) => debugPrint('Player state stream error: $e'));
    _mediaItemSub = handler.mediaItem.listen((item) {
      if (!mounted || !identical(_handler, handler)) return;
      if (item == null) {
        if (handler.songs.isEmpty && mounted) {
          state = state.copyWith(
            clearCurrentSong: true,
            queue: const [],
            position: Duration.zero,
            totalDuration: Duration.zero,
            isPlaying: false,
          );
          _widgetService.onSongCleared();
        }
        return;
      }
      final current = handler.currentSong;
      final song = current?.id == item.id
          ? current
          : handler.songs.where((s) => s.id == item.id).firstOrNull;
      if (song == null) return;
      try {
        state = state.copyWith(
          currentSong: song,
          queue: List.of(handler.songs),
          totalDuration:
              handler.player.duration ??
              Duration(milliseconds: song.durationMs),
        );
        _widgetService.onSongChanged(song, handler.isPlaying);
      } catch (e) {
        debugPrint('Media item update error: $e');
      }
    }, onError: (e) => debugPrint('Media item stream error: $e'));

    _applyDefaultPlaybackSettings(handler);

    // A song was requested while the handler was still initializing — start it now.
    final pendingSong = _pendingSong;
    final pendingQueue = _pendingQueue;
    if (pendingSong != null) {
      _pendingSong = null;
      _pendingQueue = null;
      unawaited(playSong(pendingSong, pendingQueue));
    }
  }

  void _applyDefaultPlaybackSettings(AudioPlayerHandler handler) {
    final settings = _runtimeSettings;
    if (settings.defaultShuffle) {
      unawaited(handler.setShuffle(true));
      state = state.copyWith(isShuffled: true);
    }
    if (settings.defaultRepeatMode != AppSettingsRepeatMode.off) {
      final audioServiceMode = switch (settings.defaultRepeatMode) {
        AppSettingsRepeatMode.one => AudioServiceRepeatMode.one,
        AppSettingsRepeatMode.all => AudioServiceRepeatMode.all,
        AppSettingsRepeatMode.off => AudioServiceRepeatMode.none,
      };
      unawaited(handler.setRepeatMode(audioServiceMode));
      state = state.copyWith(repeatMode: settings.defaultRepeatMode);
    }
  }

  Future<void> playSong(SongEntity song, List<SongEntity>? queue) async {
    final resolvedQueue = queue ?? [song];

    _queueVersion++;
    final version = _queueVersion;
    state = state.copyWith(
      currentSong: song,
      isPlaying: false,
      queue: resolvedQueue,
      totalDuration: Duration(milliseconds: song.durationMs),
    );

    final handler = _handler;
    if (handler == null) {
      // Audio stack still initializing — remember the intent and start
      // playback once the handler is available.
      _pendingSong = song;
      _pendingQueue = resolvedQueue;
      return;
    }
    _pendingSong = song;
    _pendingQueue = resolvedQueue;
    if (!mounted || !identical(_handler, handler)) return;
    try {
      await handler.setQueue(resolvedQueue, initialSong: song);
    } catch (error) {
      debugPrint('Failed to set queue: $error');
      if (mounted && version == _queueVersion && identical(_handler, handler)) {
        _pendingSong = null;
        _pendingQueue = null;
        _resyncStateFromHandler();
      }
      return;
    }

    if (!mounted || version != _queueVersion || !identical(_handler, handler)) {
      return;
    }
    _pendingSong = null;
    _pendingQueue = null;
    final shouldPlay = handler.wantsPlayback;
    try {
      state = state.copyWith(
        isPlaying: shouldPlay,
        totalDuration: handler.player.duration ?? state.totalDuration,
      );
    } catch (e) {
      debugPrint('Play state update error: $e');
    }

    _widgetService.onSongChanged(song, shouldPlay);
    // Play count is recorded by the audio handler when the song becomes
    // current (see background_audio_service.dart) — one increment per play,
    // regardless of how the song was started.
  }

  Future<void> togglePlayPause() async {
    final handler = _handler;
    if (handler == null) {
      _cancelPendingPlayback();
      return;
    }
    try {
      if (handler.isPlaying) {
        if (_runtimeSettings.stopOnPause) {
          await handler.stop();
        } else {
          await handler.pause();
        }
        if (!mounted || !identical(_handler, handler)) return;
        state = state.copyWith(isPlaying: false);
        _widgetService.onPlayStateChanged(false);
      } else {
        await handler.play();
        if (!mounted || !identical(_handler, handler)) return;
        state = state.copyWith(isPlaying: true);
        _widgetService.onPlayStateChanged(true);
      }
    } catch (error) {
      debugPrint('Play/pause failed: $error');
      if (mounted && identical(_handler, handler)) _resyncStateFromHandler();
    }
  }

  Future<void> play() async {
    final handler = _handler;
    if (handler == null) return;
    try {
      await handler.play();
      if (!mounted || !identical(_handler, handler)) return;
      state = state.copyWith(isPlaying: true);
      _widgetService.onPlayStateChanged(true);
    } catch (error) {
      debugPrint('Play failed: $error');
      if (mounted && identical(_handler, handler)) _resyncStateFromHandler();
    }
  }

  Future<bool> pause() async {
    final handler = _handler;
    if (handler == null) {
      _cancelPendingPlayback();
      return false;
    }
    try {
      if (_runtimeSettings.stopOnPause) {
        await handler.stop();
      } else {
        await handler.pause();
      }
    } catch (error) {
      debugPrint('Pause failed: $error');
      if (mounted && identical(_handler, handler)) _resyncStateFromHandler();
      return false;
    }
    if (!mounted || !identical(_handler, handler)) return false;
    state = state.copyWith(isPlaying: false);
    _widgetService.onPlayStateChanged(false);
    return true;
  }

  void _cancelPendingPlayback() {
    if (_pendingSong == null && _pendingQueue == null) return;
    _queueVersion++;
    _pendingSong = null;
    _pendingQueue = null;
    state = state.copyWith(
      clearCurrentSong: true,
      queue: const [],
      isPlaying: false,
      position: Duration.zero,
      totalDuration: Duration.zero,
    );
    _widgetService.onSongCleared();
  }

  Future<void> skipToNext() async {
    final handler = _handler;
    if (handler == null) return;
    try {
      await handler.skipToNext();
    } catch (error) {
      debugPrint('Skip next failed: $error');
      if (mounted && identical(_handler, handler)) _resyncStateFromHandler();
    }
  }

  Future<void> skipToPrevious() async {
    final handler = _handler;
    if (handler == null) return;
    try {
      await handler.skipToPrevious();
    } catch (error) {
      debugPrint('Skip previous failed: $error');
      if (mounted && identical(_handler, handler)) _resyncStateFromHandler();
    }
  }

  Future<void> skipToQueueItem(int index) async {
    final handler = _handler;
    if (handler == null) return;
    try {
      await handler.skipToQueueItem(index);
    } catch (error) {
      debugPrint('Queue selection failed: $error');
      if (mounted && identical(_handler, handler)) _resyncStateFromHandler();
    }
  }

  /// Adds [song] without exposing an ambiguous boolean for startup and
  /// duplicate cases.
  Future<QueueAddResult> addToQueue(
    SongEntity song, {
    bool playNext = false,
  }) async {
    final handler = _handler;
    if (handler == null) return QueueAddResult.playerUnavailable;
    _queueVersion++;
    final version = _queueVersion;
    if (_pendingSong != null) {
      final desired = List<SongEntity>.of(_pendingQueue ?? state.queue);
      if (!desired.any((queued) => queued.id == song.id)) {
        final currentId = _pendingSong!.id;
        final currentIndex = desired.indexWhere(
          (queued) => queued.id == currentId,
        );
        final insertAt = playNext
            ? (currentIndex >= 0 ? currentIndex + 1 : desired.length)
            : desired.length;
        desired.insert(insertAt, song.copyWith());
        _pendingQueue = desired;
        state = state.copyWith(queue: List.of(desired));
      }
    }

    if (!mounted || !identical(_handler, handler)) {
      return QueueAddResult.playerUnavailable;
    }
    try {
      final added = await handler.addToQueue([song], playNext: playNext);
      if (!added) {
        if (mounted && version == _queueVersion) {
          _pendingSong = null;
          _pendingQueue = null;
          _resyncStateFromHandler();
        }
        return QueueAddResult.alreadyQueued;
      }
      if (mounted && version == _queueVersion) {
        _pendingSong = null;
        _pendingQueue = null;
        _resyncStateFromHandler();
      }
      return QueueAddResult.added;
    } catch (error) {
      debugPrint('Queue insertion failed: $error');
      if (mounted && version == _queueVersion) {
        _pendingSong = null;
        _pendingQueue = null;
        _resyncStateFromHandler();
      }
      rethrow;
    }
  }

  /// Drops deleted songs from both active and pending playback state. When
  /// the current song is deleted, playback moves directly to the next
  /// surviving song while preserving whether playback was intended to run.
  Future<void> handleSongsRemoved(List<String> ids) {
    if (ids.isEmpty || !mounted) return Future<void>.value();
    return _handleSongsRemovedNow(ids);
  }

  Future<void> _handleSongsRemovedNow(List<String> ids) async {
    if (!mounted) return;
    final doomed = ids.toSet();
    final handler = _handler;
    final referenceQueue = _pendingQueue ?? handler?.songs ?? state.queue;
    final referenceCurrent = _pendingSong ?? state.currentSong;
    final affectsQueue = referenceQueue.any((song) => doomed.contains(song.id));
    final affectsCurrent =
        referenceCurrent != null && doomed.contains(referenceCurrent.id);
    if (!affectsQueue && !affectsCurrent) return;

    _queueVersion++;
    final version = _queueVersion;
    final remaining = referenceQueue
        .where((song) => !doomed.contains(song.id))
        .toList();
    final currentRemoved =
        state.currentSong != null && doomed.contains(state.currentSong!.id);
    final wasPlaying = handler?.wantsPlayback ?? state.isPlaying;

    if (_pendingQueue != null) {
      _pendingQueue = remaining;
    }
    if (_pendingSong != null && doomed.contains(_pendingSong!.id)) {
      _pendingSong = _nextSurvivingSong(
        referenceQueue,
        _pendingSong!.id,
        doomed,
      );
    }

    if (!currentRemoved) {
      state = state.copyWith(queue: remaining);
      if (handler == null) return;
      try {
        await handler.removeQueueItems(ids);
      } catch (error) {
        debugPrint('Queue prune failed: $error');
        if (mounted && version == _queueVersion) {
          _resyncStateFromHandler();
        }
        rethrow;
      }
      if (mounted && version == _queueVersion) {
        _pendingSong = null;
        _pendingQueue = null;
        _resyncQueueFromHandler();
      }
      return;
    }

    final next = _nextSurvivingSong(state.queue, state.currentSong!.id, doomed);
    state = state.copyWith(
      queue: remaining,
      currentSong: next,
      clearCurrentSong: next == null,
      isPlaying: next != null && wasPlaying,
      position: Duration.zero,
      totalDuration: next == null
          ? Duration.zero
          : Duration(milliseconds: next.durationMs),
    );
    final shouldPlay = next != null && wasPlaying;
    if (next != null) {
      _widgetService.onSongChanged(next, shouldPlay);
    } else {
      _widgetService.onSongCleared();
    }

    if (handler == null) {
      if (next != null) {
        _pendingSong = next;
        _pendingQueue = remaining;
      }
      return;
    }
    try {
      if (next != null) {
        await handler.setQueue(
          remaining,
          initialSong: next,
          playWhenReady: wasPlaying,
        );
      } else {
        await handler.setQueue([], playWhenReady: false);
      }
    } catch (error) {
      debugPrint('Queue rebuild after song removal failed: $error');
      if (mounted && version == _queueVersion) {
        _resyncStateFromHandler();
      }
      rethrow;
    }
    if (mounted && version == _queueVersion) {
      _pendingSong = null;
      _pendingQueue = null;
      _resyncQueueFromHandler();
    }
  }

  SongEntity? _nextSurvivingSong(
    List<SongEntity> queue,
    String currentId,
    Set<String> doomed,
  ) {
    SongEntity? fallback;
    var seenCurrent = false;
    for (final song in queue) {
      if (song.id == currentId) {
        seenCurrent = true;
        continue;
      }
      if (doomed.contains(song.id)) continue;
      if (seenCurrent) return song;
      fallback ??= song;
    }
    return fallback;
  }

  Future<void> seek(Duration position) async {
    final handler = _handler;
    if (handler == null) return;
    try {
      await handler.seek(position);
      if (mounted && identical(_handler, handler)) {
        state = state.copyWith(position: position);
      }
    } catch (error) {
      debugPrint('Seek failed: $error');
      if (mounted && identical(_handler, handler)) {
        _resyncStateFromHandler();
      }
    }
  }

  void setVolume(double volume) {
    final handler = _handler;
    if (handler == null) return;
    handler.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  Future<void> setShuffle(bool enabled) async {
    final handler = _handler;
    if (handler == null) return;
    _queueVersion++;
    final version = _queueVersion;
    if (!mounted || !identical(_handler, handler)) return;
    try {
      await handler.setShuffle(enabled);
    } catch (error) {
      debugPrint('Queue shuffle failed: $error');
      if (mounted && version == _queueVersion) {
        _pendingSong = null;
        _pendingQueue = null;
        _resyncStateFromHandler();
      }
      rethrow;
    }
    if (!mounted || version != _queueVersion) return;
    _pendingSong = null;
    _pendingQueue = null;
    // Re-sync the UI queue with the (possibly reordered) handler queue so
    // skipToQueueItem/reorderQueue indices always agree.
    _resyncStateFromHandler();
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

  void applyCommittedSong(SongEntity song) {
    if (!mounted) return;
    final current = state.currentSong;
    final isCurrent = current?.id == song.id;
    state = state.copyWith(
      currentSong: isCurrent ? song.copyWith() : null,
      queue: [
        for (final queued in state.queue)
          if (queued.id == song.id) song.copyWith() else queued,
      ],
    );
    if (_pendingSong?.id == song.id) _pendingSong = song.copyWith();
    if (_pendingQueue != null) {
      _pendingQueue = [
        for (final queued in _pendingQueue!)
          if (queued.id == song.id) song.copyWith() else queued,
      ];
    }
    _handler?.applyCommittedSong(song);
    if (isCurrent) {
      _widgetService.onSongChanged(song, state.isPlaying);
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    // oldIndex/newIndex use onReorderItem semantics (pre-adjusted: the item
    // was already removed before newIndex was computed), so the move is a
    // plain removeAt/insert with no extra index adjustment.
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    if (newIndex < 0 || newIndex >= state.queue.length) return;
    if (oldIndex == newIndex) return;

    // Optimistic UI update FIRST: ReorderableListView expects its backing
    // list to reflect the drop synchronously, otherwise the dragged row
    // snaps back and a second quick drag computes indices against stale
    // state.
    final songs = List<SongEntity>.from(state.queue);
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);
    _queueVersion++;
    final version = _queueVersion;
    state = state.copyWith(queue: songs);
    if (_pendingSong != null) _pendingQueue = List.of(songs);

    final handler = _handler;
    if (handler == null) return;

    // The handler owns the authoritative order (and the loaded audio
    // source). On completion, resync from it instead of replaying the
    // indices — replaying would double-apply the move whenever the
    // handler's mediaItem emission already synced state.queue first.
    unawaited(() async {
      if (!mounted || !identical(_handler, handler)) return;
      try {
        await handler.reorderQueue(oldIndex, newIndex);
      } catch (error) {
        debugPrint('Queue reorder failed: $error');
        if (version == _queueVersion) _resyncStateFromHandler();
        return;
      }
      if (version != _queueVersion || !identical(_handler, handler)) return;
      _pendingSong = null;
      _pendingQueue = null;
      _resyncStateFromHandler();
    }());
  }

  /// Copies the handler's authoritative queue order into UI state when it
  /// has actually diverged (avoids needless rebuilds on every call).
  void _resyncQueueFromHandler() {
    if (!mounted) return;
    final handler = _handler;
    if (handler == null) return;
    final handlerSongs = handler.songs;
    final current = state.queue;
    if (handlerSongs.length != current.length) {
      state = state.copyWith(queue: List.of(handlerSongs));
      return;
    }
    for (var i = 0; i < handlerSongs.length; i++) {
      if (!identical(handlerSongs[i], current[i]) &&
          handlerSongs[i].id != current[i].id) {
        state = state.copyWith(queue: List.of(handlerSongs));
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncStateFromHandler();
    }
  }

  void _resyncStateFromHandler() {
    if (!mounted) return;
    final handler = _handler;
    if (handler == null) return;
    try {
      final song = handler.currentSong;
      state = state.copyWith(
        currentSong: song,
        clearCurrentSong: song == null,
        queue: List.of(handler.songs),
        isPlaying: handler.isPlaying,
        position: handler.player.position,
        totalDuration:
            handler.player.duration ??
            (song == null
                ? Duration.zero
                : Duration(milliseconds: song.durationMs)),
      );
      if (song == null) {
        _widgetService.onSongCleared();
      } else {
        _widgetService.onSongChanged(song, handler.isPlaying);
      }
    } catch (error) {
      debugPrint('Audio state resync error: $error');
    }
  }

  Future<void> _syncStateFromHandler() async {
    _resyncStateFromHandler();
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
    bool clearCurrentSong = false,
    bool? isPlaying,
    Duration? position,
    Duration? totalDuration,
    List<SongEntity>? queue,
    bool? isShuffled,
    AppSettingsRepeatMode? repeatMode,
    double? volume,
  }) {
    return AudioPlayerState(
      currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
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
