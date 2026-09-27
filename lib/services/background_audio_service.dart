import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/domain/entities/app_settings.dart';

enum _CrossfadeState { idle, preloading, fading, transitioning }

class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  late final AudioPlayer player;
  late final AudioPlayer _crossfadePlayer;
  List<SongEntity> _queue = [];
  List<SongEntity> _orderedQueue = [];
  int _currentIndex = 0;
  bool _isShuffled = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  MediaItem? _lastMediaItem;
  bool _wantPlaying = false;
  ConcatenatingAudioSource? _source;
  Duration _lastPosition = Duration.zero;
  int _queueMutationGeneration = 0;
  int _playbackIntentGeneration = 0;
  bool _queueMutationInProgress = false;
  bool _sourceNeedsReconciliation = false;
  // One FIFO serializes every structural queue mutation. Native source moves,
  // rebuilds, and full replacements can therefore never interleave.
  Future<void> _queueMutationChain = Future<void>.value();

  /// Play-count state is separate from media publication. A run is prepared
  /// only for an intended playback start and committed after the main player
  /// demonstrates forward progress.
  int _playbackRun = 0;
  int? _activePlaybackRun;
  int? _pendingPlayCountRun;
  bool _playbackStartPending = false;
  Duration _playbackStartPosition = Duration.zero;
  int? _countedRun;
  int _countedIndex = -1;
  SongEntity? _countedSong;
  final Map<String, SongEntity> _committedSongMetadata = {};
  final Future<void> Function(SongEntity song) _playCountRecorder;

  /// While true, the current-index handler updates [_currentIndex] but does
  /// NOT emit mediaItem/play-count events. Used during in-place source
  /// reorders (shuffle toggles, queue reorders), where every move() fires an
  /// intermediate currentIndex event that would otherwise flash wrong songs
  /// in the Now Playing UI. The settled song is re-emitted once the reorder
  /// completes.
  bool _suppressCurrentSongEvents = false;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<ProcessingState>? _processingStateSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PositionDiscontinuity>? _positionDiscontinuitySub;

  // Crossfade state
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 300;
  bool _autoplayEnabled = true;
  Timer? _crossfadeTimer;
  Timer? _fadeOutTimer;
  int _crossfadeSeq = 0;
  int _runtimeSettingsGeneration = 0;
  int _autoplayGeneration = 0;
  int? _preloadedCrossfadeIndex;
  double _userVolume = 1.0;
  bool _skipInProgress = false;
  Future<void> _crossfadeOperationQueue = Future<void>.value();
  _CrossfadeState _crossfadeState = _CrossfadeState.idle;
  // True while our state machine is actively performing the handoff.
  // Prevents positionDiscontinuityStream autoAdvance from cancelling our own transition.
  bool _owningTransition = false;

  static Future<void> _defaultPlayCountRecorder(SongEntity song) async {
    await HiveStorage.incrementPlayCount(song.id);
  }

  AudioPlayerHandler({
    AppSettings? initialSettings,
    AudioPlayer? mainPlayer,
    AudioPlayer? crossfadePlayer,
    Future<void> Function(SongEntity song)? playCountRecorder,
  }) : _playCountRecorder = playCountRecorder ?? _defaultPlayCountRecorder {
    final settings = initialSettings ?? HiveStorage.getSettings();
    _crossfadeEnabled = settings.crossfadeEnabled;
    _crossfadeDurationMs = settings.crossfadeDurationMs;
    _autoplayEnabled = settings.autoplayEnabled;
    try {
      player = mainPlayer ?? AudioPlayer();
      _crossfadePlayer =
          crossfadePlayer ?? AudioPlayer(handleInterruptions: false);
    } catch (e) {
      debugPrint('Failed to initialize AudioPlayer: $e');
      rethrow;
    }

    playbackState.add(
      PlaybackState(
        playing: false,
        processingState: AudioProcessingState.idle,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );

    _positionSub = player.positionStream.listen(
      (pos) {
        _lastPosition = pos;
        if (_playbackStartPending && pos > _playbackStartPosition) {
          _playbackStartPending = false;
          final run = _activePlaybackRun ?? _pendingPlayCountRun;
          if (run != null) _recordCurrentSongPlay(run, isPlaying: true);
        }
        try {
          if (_crossfadeEnabled &&
              player.playing &&
              _crossfadeState == _CrossfadeState.idle) {
            _startCrossfadeMonitor();
          }
          playbackState.add(
            playbackState.value.copyWith(
              updatePosition: pos,
              systemActions: {MediaAction.seek},
            ),
          );
        } catch (e) {
          debugPrint('Position stream error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('Position stream error: $e');
      },
    );

    _durationSub = player.durationStream.listen(
      (duration) {
        try {
          final item = _lastMediaItem;
          if (item == null || duration == null || duration <= Duration.zero) {
            return;
          }
          if (item.duration == duration) return;
          if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
          if (_queue[_currentIndex].id != item.id) return;
          _lastMediaItem = item.copyWith(duration: duration);
          mediaItem.add(_lastMediaItem!);
        } catch (e) {
          debugPrint('Duration stream error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('Duration stream error: $e');
      },
    );

    _currentIndexSub = player.currentIndexStream.listen(
      (index) {
        try {
          if (index == null || index < 0 || index >= _queue.length) return;
          _skipInProgress = false;
          _currentIndex = index;
          if (!_suppressCurrentSongEvents) {
            _emitCurrentSong();
          }
          playbackState.add(
            playbackState.value.copyWith(
              queueIndex: index,
              systemActions: {MediaAction.seek},
              androidCompactActionIndices: const [0, 1, 2],
            ),
          );
        } catch (e) {
          debugPrint('Current index stream error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('Current index stream error: $e');
      },
    );

    _playerStateSub = player.playerStateStream.listen(
      (state) {
        try {
          final processingState = _mapProcessingState(state.processingState);
          if (!state.playing) _playbackStartPending = false;
          playbackState.add(
            playbackState.value.copyWith(
              playing: state.playing,
              processingState: processingState,
              controls: [
                MediaControl.skipToPrevious,
                if (state.playing) MediaControl.pause else MediaControl.play,
                MediaControl.skipToNext,
              ],
              updatePosition: player.position,
              bufferedPosition: player.bufferedPosition,
              speed: 1.0,
              queueIndex: _currentIndex,
              systemActions: {MediaAction.seek},
              androidCompactActionIndices: const [0, 1, 2],
            ),
          );
        } catch (e) {
          debugPrint('Player state stream error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('Player state stream error: $e');
      },
    );

    _processingStateSub = player.processingStateStream.listen(
      (state) {
        try {
          if (state == ProcessingState.completed) {
            if (_repeatMode == AudioServiceRepeatMode.one ||
                _repeatMode == AudioServiceRepeatMode.all) {
              // LoopMode.one / LoopMode.all: let just_audio handle the native
              // loop internally.  ExoPlayer briefly emits STATE_ENDED before
              // looping back, which would otherwise trigger _finishQueue()
              // and break the loop.
              return;
            }
            _finishQueue();
          }
        } catch (e) {
          debugPrint('Processing state stream error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('Processing state stream error: $e');
      },
    );

    _positionDiscontinuitySub = player.positionDiscontinuityStream.listen(
      (discontinuity) {
        if (discontinuity.reason == PositionDiscontinuityReason.autoAdvance) {
          if (_owningTransition) {
            debugPrint(
              'Crossfade: autoAdvance during our transition — ignoring (state=$_crossfadeState)',
            );
            return;
          }
          if (_crossfadeState == _CrossfadeState.fading ||
              _crossfadeState == _CrossfadeState.transitioning) {
            debugPrint(
              'Crossfade: unexpected autoAdvance (state=$_crossfadeState), cancelling',
            );
            _cancelCrossfade(restoreVolume: true);
          }
        }
      },
      onError: (Object e) {
        debugPrint('Position discontinuity stream error: $e');
      },
    );

    _initCrossfade();
  }

  void _initCrossfade() {
    _currentIndexSub?.cancel();
    _currentIndexSub = player.currentIndexStream.listen(
      (index) {
        try {
          if (index == null || index < 0 || index >= _queue.length) return;
          final wasSkipping = _skipInProgress;
          _skipInProgress = false;
          final prevIndex = _currentIndex;
          _currentIndex = index;
          if (prevIndex != index &&
              player.playing &&
              !_suppressCurrentSongEvents &&
              _pendingPlayCountRun == null) {
            _activePlaybackRun = null;
            _preparePlaybackRun();
            _playbackStartPending = true;
            _playbackStartPosition = Duration.zero;
          }

          // If currentIndex changed due to our explicit crossfade transition,
          // complete the crossfade. Otherwise let the crossfade monitor own
          // the transition timing. A structural queue mutation owns the native
          // index events until its final queue has been published.
          if (!_queueMutationInProgress) {
            if (_crossfadeEnabled &&
                prevIndex != index &&
                _crossfadeState == _CrossfadeState.transitioning &&
                !wasSkipping) {
              unawaited(_completeCrossfade(index));
            } else if (_crossfadeState == _CrossfadeState.idle) {
              unawaited(_preloadNextTrack());
            }

            if (!_suppressCurrentSongEvents) {
              _emitCurrentSong();
            }
          }
          playbackState.add(
            playbackState.value.copyWith(
              queueIndex: index,
              systemActions: {MediaAction.seek},
              androidCompactActionIndices: const [0, 1, 2],
            ),
          );
        } catch (e) {
          debugPrint('Current index stream error: $e');
        }
      },
      onError: (Object e) {
        debugPrint('Current index stream error: $e');
      },
    );
  }

  /// Applies a settings snapshot after it has been committed to storage. No
  /// live decision in the handler reads the settings cache.
  void updateRuntimeSettings(AppSettings settings) {
    final crossfadeChanged =
        _crossfadeEnabled != settings.crossfadeEnabled ||
        _crossfadeDurationMs != settings.crossfadeDurationMs;
    final autoplayChanged = _autoplayEnabled != settings.autoplayEnabled;
    if (crossfadeChanged) _runtimeSettingsGeneration++;
    if (autoplayChanged) _autoplayGeneration++;
    _crossfadeEnabled = settings.crossfadeEnabled;
    _crossfadeDurationMs = settings.crossfadeDurationMs;
    _autoplayEnabled = settings.autoplayEnabled;
    if (!_crossfadeEnabled || crossfadeChanged || autoplayChanged) {
      _cancelCrossfade(restoreVolume: true);
    }
    if (autoplayChanged &&
        !_autoplayEnabled &&
        player.processingState == ProcessingState.completed) {
      unawaited(_finishQueue());
    } else if (_crossfadeEnabled &&
        _wantPlaying &&
        _crossfadeState == _CrossfadeState.idle) {
      unawaited(_preloadNextTrack());
    }
  }

  void _startCrossfadeMonitor() {
    if (!_crossfadeEnabled ||
        !player.playing ||
        _crossfadeState != _CrossfadeState.idle ||
        _crossfadeTimer?.isActive == true) {
      return;
    }

    _crossfadeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _checkCrossfade();
    });
  }

  void _checkCrossfade() {
    if (!_crossfadeEnabled ||
        !player.playing ||
        _crossfadeState != _CrossfadeState.idle) {
      return;
    }

    final pos = player.position;
    final dur = player.duration;
    if (dur == null || dur <= Duration.zero) return;

    final remaining = dur - pos;
    final crossfadeDur = Duration(milliseconds: _crossfadeDurationMs);
    final nextIndex = _nextCrossfadeIndex();

    debugPrint(
      'Crossfade: check idx=$_currentIndex rem=${remaining.inSeconds}s '
      'fadeDur=${_crossfadeDurationMs}ms next=$nextIndex state=$_crossfadeState',
    );

    if (remaining <= crossfadeDur && remaining > Duration.zero) {
      if (nextIndex == null) return;
      if (_preloadedCrossfadeIndex != nextIndex) {
        debugPrint('Crossfade: entering preloading state');
        _crossfadeState = _CrossfadeState.preloading;
        unawaited(_preloadNextTrack());
        return;
      }
      debugPrint(
        'Crossfade: starting fade out (remaining=${remaining.inSeconds}s)',
      );
      _startFadeOut(remaining);
    }
  }

  int? _nextCrossfadeIndex() {
    if (_repeatMode == AudioServiceRepeatMode.one || _queue.length < 2) {
      return null;
    }
    final nextIndex = _currentIndex + 1;
    if (nextIndex < _queue.length) return nextIndex;
    return _repeatMode != AudioServiceRepeatMode.none || _autoplayEnabled
        ? 0
        : null;
  }

  Future<void> _preloadNextTrack() async {
    if (!_crossfadeEnabled ||
        _queueMutationInProgress ||
        _crossfadeState == _CrossfadeState.fading ||
        _crossfadeState == _CrossfadeState.transitioning) {
      return;
    }
    final seq = ++_crossfadeSeq;
    final queueGeneration = _queueMutationGeneration;
    final settingsGeneration = _runtimeSettingsGeneration;
    final nextIndex = _nextCrossfadeIndex();
    if (nextIndex == null) return;
    // Don't preload if we've already moved on or cancelled.
    if (_crossfadeState == _CrossfadeState.idle &&
        _preloadedCrossfadeIndex == nextIndex) {
      return;
    }
    try {
      final nextSong = _queue[nextIndex];
      await _runCrossfadeOperation(() async {
        if (_crossfadeSeq != seq ||
            _queueMutationInProgress ||
            _runtimeSettingsGeneration != settingsGeneration) {
          return;
        }
        await _crossfadePlayer.setAudioSource(_songToAudioSource(nextSong));
        await _crossfadePlayer.setVolume(0.0);
      });
      // Verify this preload still belongs to the current queue and transition.
      if (_crossfadeSeq != seq ||
          _queueMutationGeneration != queueGeneration ||
          _runtimeSettingsGeneration != settingsGeneration ||
          _queueMutationInProgress) {
        return;
      }
      _preloadedCrossfadeIndex = nextIndex;
      if (_crossfadeState == _CrossfadeState.preloading) {
        _startFadeOut(player.duration ?? Duration.zero);
      }
    } catch (e) {
      if (_crossfadeSeq == seq) {
        _preloadedCrossfadeIndex = null;
        _crossfadeState = _CrossfadeState.idle;
        if (player.processingState == ProcessingState.completed &&
            _wantPlaying &&
            _autoplayEnabled &&
            !_queueMutationInProgress) {
          unawaited(_finishQueue());
        }
      }
      debugPrint('Failed to preload crossfade track: $e');
    }
  }

  void _startFadeOut(Duration remaining) {
    if (_crossfadeState != _CrossfadeState.idle &&
        _crossfadeState != _CrossfadeState.preloading) {
      return;
    }
    final nextIndex = _nextCrossfadeIndex();
    if (nextIndex == null || _preloadedCrossfadeIndex != nextIndex) {
      _crossfadeState = _CrossfadeState.idle;
      return;
    }

    // Clamp fade duration to track length so short tracks don't freeze.
    final effectiveFadeMs = remaining.inMilliseconds.clamp(
      0,
      _crossfadeDurationMs,
    );
    if (effectiveFadeMs <= 0) {
      // Track is essentially over; transition immediately.
      _crossfadeState = _CrossfadeState.transitioning;
      unawaited(_performTransition(nextIndex));
      return;
    }

    _crossfadeState = _CrossfadeState.fading;
    final steps = 20;
    final stepMs = (effectiveFadeMs / steps).clamp(5.0, 50.0).toInt();
    int step = 0;

    debugPrint(
      'Crossfade: fade started idx=$_currentIndex next=$nextIndex '
      'dur=${_crossfadeDurationMs}ms steps=$steps stepMs=$stepMs',
    );

    // Start the next track on the crossfade player without waiting for the
    // playback-lifecycle future to complete.
    unawaited(
      _crossfadePlayer.play().catchError((Object error) {
        debugPrint('Failed to start crossfade player: $error');
      }),
    );

    _fadeOutTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
      if (_crossfadeState != _CrossfadeState.fading) {
        timer.cancel();
        _fadeOutTimer = null;
        return;
      }
      step++;
      final rawT = step / steps;
      // Equal-power (sine) crossfade curve:
      //   current = cos(π/2 * t), next = sin(π/2 * t)
      final t = rawT.clamp(0.0, 1.0);
      final currentVol = _userVolume * _cosFade(t);
      final nextVol = _userVolume * _sinFade(t);
      player.setVolume(currentVol);
      _crossfadePlayer.setVolume(nextVol);

      debugPrint(
        'Crossfade: step $step/$steps t=$rawT '
        'A=${currentVol.toStringAsFixed(2)} B=${nextVol.toStringAsFixed(2)} '
        'cfPos=${_crossfadePlayer.position}',
      );

      if (step >= steps) {
        timer.cancel();
        _fadeOutTimer = null;
        debugPrint('Crossfade: fade complete, handoff to transitioning');
        _crossfadeState = _CrossfadeState.transitioning;
        unawaited(_performTransition(nextIndex));
      }
    });
  }

  /// Equal-power crossfade: cos(π/2 * t) — starts at 1, ends at 0.
  double _cosFade(double t) => cos(t * 1.57079632679);

  /// Equal-power crossfade: sin(π/2 * t) — starts at 0, ends at 1.
  double _sinFade(double t) => sin(t * 1.57079632679);

  Future<void> _runCrossfadeOperation(Future<void> Function() operation) {
    final completer = Completer<void>();
    _crossfadeOperationQueue = _crossfadeOperationQueue.then((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _recoverFailedCrossfadeTransition() async {
    _sourceNeedsReconciliation = true;
    _source = null;
    if (_wantPlaying && _autoplayEnabled) {
      unawaited(_finishQueue());
      return;
    }

    try {
      await _enqueueSerializedCommand(() async {
        await _rebuildSourceKeepingPlayback(Duration.zero);
        _sourceNeedsReconciliation = false;
      });
    } catch (error) {
      debugPrint('Failed to rebuild source after crossfade error: $error');
    }
  }

  Future<void> _performTransition(int index) async {
    if (_crossfadeState != _CrossfadeState.transitioning) return;
    final crossfadeSeq = _crossfadeSeq;
    final queueGeneration = _queueMutationGeneration;
    final settingsGeneration = _runtimeSettingsGeneration;
    bool transitionIsCurrent() =>
        _crossfadeSeq == crossfadeSeq &&
        _queueMutationGeneration == queueGeneration &&
        _runtimeSettingsGeneration == settingsGeneration &&
        !_queueMutationInProgress;
    debugPrint(
      'Crossfade: _performTransition idx=$index pos=${_crossfadePlayer.position}',
    );
    _owningTransition = true;
    var transitionFailed = false;
    int? preparedRun;
    // Capture the crossfade player's position before stopping it so the main
    // player picks up song B from where the crossfade left off.
    final crossfadePosition = _crossfadePlayer.position;
    // Stop the crossfade player first to avoid double audio.
    try {
      await _runCrossfadeOperation(_crossfadePlayer.stop);
    } catch (e) {
      transitionFailed = true;
      debugPrint('Failed to stop crossfade player: $e');
      try {
        await _runCrossfadeOperation(_crossfadePlayer.pause);
      } catch (pauseError) {
        debugPrint(
          'Failed to pause crossfade player after stop error: $pauseError',
        );
        try {
          await _runCrossfadeOperation(() => _crossfadePlayer.setVolume(0.0));
        } catch (muteError) {
          debugPrint(
            'Failed to mute crossfade player after stop error: $muteError',
          );
        }
      }
    }
    if (!transitionIsCurrent()) {
      _owningTransition = false;
      return;
    }
    _preloadedCrossfadeIndex = null;
    if (transitionFailed) {
      _owningTransition = false;
      _crossfadeState = _CrossfadeState.idle;
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      await _recoverFailedCrossfadeTransition();
      return;
    }

    _activePlaybackRun = null;
    _preparePlaybackRun();
    preparedRun = _pendingPlayCountRun;
    // Explicitly seek main player to next track at the crossfade position.
    try {
      await _enqueueSerializedCommand(() async {
        if (!transitionIsCurrent()) return;
        await player.seek(crossfadePosition, index: index);
        await player.setVolume(_userVolume);
      });
    } catch (e) {
      transitionFailed = true;
      debugPrint('Failed to perform crossfade transition: $e');
      await player.setVolume(_userVolume).catchError((Object _) {});
    }
    if (!transitionIsCurrent()) {
      _discardPreparedPlaybackRun(preparedRun);
      _owningTransition = false;
      return;
    }
    _owningTransition = false;
    _crossfadeState = _CrossfadeState.idle;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    if (transitionFailed) {
      _discardPreparedPlaybackRun(preparedRun);
      await _recoverFailedCrossfadeTransition();
      return;
    }
    _playbackStartPending = true;
    _playbackStartPosition = crossfadePosition;
    if (_wantPlaying && !player.playing) _startPlaybackIfRequested();
    unawaited(_preloadNextTrack());
  }

  Future<void> _completeCrossfade(int index) async {
    final crossfadeSeq = _crossfadeSeq;
    final queueGeneration = _queueMutationGeneration;
    final settingsGeneration = _runtimeSettingsGeneration;
    debugPrint(
      'Crossfade: _completeCrossfade idx=$index state=$_crossfadeState '
      'owning=$_owningTransition',
    );
    // This is called when currentIndexStream fires after our explicit
    // transition. Clean up any remaining state.
    try {
      await player.setVolume(_userVolume);
    } catch (e) {
      debugPrint('Failed to restore volume in crossfade completion: $e');
    }
    if (_crossfadeSeq != crossfadeSeq ||
        _queueMutationGeneration != queueGeneration ||
        _runtimeSettingsGeneration != settingsGeneration ||
        _queueMutationInProgress) {
      return;
    }
    // The explicit transition owns cleanup and the next preload. Returning here
    // avoids incrementing [_crossfadeSeq] from that preload and invalidating
    // the transition while its post-seek generation check is still pending.
    if (_owningTransition) return;
    _preloadedCrossfadeIndex = null;
    _crossfadeState = _CrossfadeState.idle;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    unawaited(_preloadNextTrack());
  }

  void _cancelCrossfade({bool restoreVolume = true}) {
    _crossfadeSeq++;
    _owningTransition = false;
    debugPrint(
      'Crossfade: cancel state=$_crossfadeState owning=$_owningTransition '
      'cfPlaying=${_crossfadePlayer.playing} cfPos=${_crossfadePlayer.position}',
    );
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _fadeOutTimer?.cancel();
    _fadeOutTimer = null;
    if (_crossfadePlayer.playing) {
      unawaited(
        _runCrossfadeOperation(_crossfadePlayer.stop).catchError((
          Object error,
        ) {
          debugPrint('Failed to stop crossfade player during cancel: $error');
        }),
      );
    }
    _crossfadeState = _CrossfadeState.idle;
    _preloadedCrossfadeIndex = null;
    if (restoreVolume) {
      _restoreVolume();
    }
  }

  void _restoreVolume() {
    player.setVolume(_userVolume);
  }

  void _cancelCrossfadeAndRestore() {
    _cancelCrossfade(restoreVolume: true);
  }

  Duration get position => player.position;
  Duration get duration => player.duration ?? Duration.zero;
  bool get isPlaying => player.playing;
  int get currentIndex => _currentIndex;
  List<SongEntity> get songs => _queue;
  @visibleForTesting
  List<String> get sourceSongIds => [
    for (final child in _source?.children ?? const <AudioSource>[])
      if (child is IndexedAudioSource && child.tag is SongEntity)
        (child.tag as SongEntity).id,
  ];
  bool get isShuffled => _isShuffled;
  AudioServiceRepeatMode get currentRepeatMode => _repeatMode;
  @visibleForTesting
  bool get hasCommittedPlaybackRunForTesting => _countedRun != null;
  @visibleForTesting
  bool get isPlaybackStartPendingForTesting => _playbackStartPending;
  @visibleForTesting
  int? get pendingPlaybackRunForTesting => _pendingPlayCountRun;

  void setVolume(double volume) {
    _userVolume = volume;
    if (_crossfadeState == _CrossfadeState.idle) {
      player.setVolume(volume);
    }
  }

  /// The last requested playback intent. This remains false after stop/pause
  /// even though just_audio may keep its source loaded.
  bool get wantsPlayback => _wantPlaying;

  int _beginQueueMutation() {
    final generation = ++_queueMutationGeneration;
    _queueMutationInProgress = true;
    _cancelCrossfade(restoreVolume: true);
    return generation;
  }

  Future<T> _enqueueSerializedCommand<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queueMutationChain = _queueMutationChain.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<T> _enqueueQueueMutation<T>(
    Future<T> Function(int generation) operation,
  ) {
    final generation = _beginQueueMutation();
    return _enqueueSerializedCommand(() async {
      try {
        if (_sourceNeedsReconciliation) {
          await _repairSourceAfterFailure();
        }
        final result = await operation(generation);
        if (generation == _queueMutationGeneration) {
          _queueMutationInProgress = false;
          _publishQueueState(generation);
          _startPlaybackIfRequested(generation: generation);
        }
        return result;
      } catch (error, stackTrace) {
        _sourceNeedsReconciliation = true;
        _source = null;
        try {
          await _repairSourceAfterFailure();
        } catch (repairError) {
          debugPrint('Failed to repair source after queue error: $repairError');
        }
        if (generation == _queueMutationGeneration) {
          _queueMutationInProgress = false;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> _repairSourceAfterFailure() async {
    if (_queue.isEmpty) {
      _source = null;
      _sourceNeedsReconciliation = false;
      return;
    }
    final position = player.processingState == ProcessingState.idle
        ? _lastPosition
        : player.position;
    await _rebuildSourceKeepingPlayback(position);
    _sourceNeedsReconciliation = false;
  }

  void _publishQueueState(int generation) {
    if (generation != _queueMutationGeneration) return;
    if (_queue.isEmpty) {
      queue.add(const []);
      mediaItem.add(null);
      return;
    }
    queue.add(_queue.map(_songToMediaItem).toList());
    _emitCurrentSong();
    if (_crossfadeEnabled && _wantPlaying) {
      unawaited(_preloadNextTrack());
    }
  }

  void _setPlaybackIntent(bool value) {
    _wantPlaying = value;
    _playbackIntentGeneration++;
  }

  void _preparePlaybackRun() {
    _countedRun = null;
    _countedIndex = -1;
    _countedSong = null;
    _pendingPlayCountRun = ++_playbackRun;
  }

  void _discardPreparedPlaybackRun(int? run) {
    if (run == null || run != _pendingPlayCountRun) return;
    _pendingPlayCountRun = null;
    _activePlaybackRun = null;
    _playbackStartPending = false;
  }

  void _recordCurrentSongPlay(int run, {bool? isPlaying}) {
    if (!(isPlaying ?? player.playing) ||
        _suppressCurrentSongEvents ||
        _currentIndex < 0 ||
        _currentIndex >= _queue.length) {
      return;
    }
    _activePlaybackRun = run;
    if (run == _pendingPlayCountRun) _pendingPlayCountRun = null;
    final song = _queue[_currentIndex];
    if (_countedRun == run &&
        _countedIndex == _currentIndex &&
        identical(_countedSong, song)) {
      return;
    }
    _countedRun = run;
    _countedIndex = _currentIndex;
    _countedSong = song;
    unawaited(
      _playCountRecorder(song).then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          debugPrint('Failed to increment play count for ${song.id}: $error');
        },
      ),
    );
  }

  void _startPlaybackIfRequested({int? generation}) {
    final startGeneration = generation ?? _queueMutationGeneration;
    if ((generation != null && generation != _queueMutationGeneration) ||
        !_wantPlaying ||
        _queue.isEmpty) {
      return;
    }
    if (!player.playing && _pendingPlayCountRun == null) {
      _preparePlaybackRun();
    }
    if (_crossfadeEnabled) {
      _startCrossfadeMonitor();
      unawaited(_preloadNextTrack());
    }
    try {
      final wasPlaying = player.playing;
      final run = _activePlaybackRun ?? _pendingPlayCountRun;
      if (wasPlaying) {
        if (run != null) {
          _playbackStartPending = true;
          _playbackStartPosition = player.position;
        } else {
          _playbackStartPending = false;
        }
      } else if (run != null) {
        _playbackStartPending = true;
        _playbackStartPosition = player.position;
      }
      final playback = player.play();
      unawaited(
        playback.catchError((Object error) {
          if (startGeneration == _queueMutationGeneration) {
            _setPlaybackIntent(false);
            _pendingPlayCountRun = null;
            _playbackStartPending = false;
          }
          debugPrint('Failed to start playback: $error');
        }),
      );
    } catch (error) {
      if (startGeneration == _queueMutationGeneration) {
        _setPlaybackIntent(false);
        _pendingPlayCountRun = null;
        _playbackStartPending = false;
      }
      debugPrint('Failed to start playback: $error');
    }
  }

  Future<void> _buildSource() async {
    if (_queue.isEmpty) return;
    _source = ConcatenatingAudioSource(
      children: [for (final song in _queue) _songToAudioSource(song)],
    );
  }

  Future<void> setQueue(
    List<SongEntity> songs, {
    SongEntity? initialSong,
    bool playWhenReady = true,
  }) {
    // Publish the latest playback intent synchronously. A pause issued while
    // this operation is queued/loading therefore wins over the original play
    // request without ever starting and then pausing audible playback.
    _setPlaybackIntent(songs.isNotEmpty && playWhenReady);
    if (_wantPlaying) {
      _preparePlaybackRun();
    } else {
      _pendingPlayCountRun = null;
      _activePlaybackRun = null;
      _playbackStartPending = false;
    }
    return _enqueueQueueMutation(
      (_) => _setQueue(songs, initialSong: initialSong),
    );
  }

  Future<void> _setQueue(
    List<SongEntity> songs, {
    SongEntity? initialSong,
  }) async {
    if (songs.isEmpty) {
      _queue = const [];
      _orderedQueue = const [];
      _source = null;
      _currentIndex = 0;
      _lastMediaItem = null;
      _lastPosition = Duration.zero;
      await player.stop();
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          systemActions: {MediaAction.seek},
          androidCompactActionIndices: const [0, 1, 2],
        ),
      );
      return;
    }

    _queue = [for (final song in songs) _preferCommittedSong(song)];
    if (_isShuffled) {
      _queue.shuffle();
    }
    _orderedQueue = [for (final song in songs) _preferCommittedSong(song)];
    _lastPosition = Duration.zero;
    await _buildSource();
    final source = _source;
    if (source == null) {
      throw StateError('Unable to build audio source for queue');
    }

    var startIndex = 0;
    if (initialSong != null) {
      startIndex = _queue.indexWhere((song) => song.id == initialSong.id);
      if (startIndex == -1) startIndex = 0;
    }
    _currentIndex = startIndex;

    // The request may have been superseded while this source was loading. The
    // native mutation still finishes in FIFO order so the source and logical
    // queue stay aligned; only the latest generation publishes events or starts
    // playback.
    _suppressCurrentSongEvents = true;
    try {
      await player.setAudioSource(
        source,
        initialIndex: startIndex,
        initialPosition: Duration.zero,
        preload: _wantPlaying,
      );
    } finally {
      _suppressCurrentSongEvents = false;
    }
  }

  Future<void> _loadSource({
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    if (_source == null || _queue.isEmpty) return;
    await player.setAudioSource(
      _source!,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
  }

  Future<void> _playAtCore(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;

    if (player.processingState != ProcessingState.idle && _source != null) {
      await player.seek(Duration.zero, index: index);
      return;
    }
    await _loadSource(initialIndex: index, initialPosition: Duration.zero);
  }

  Future<void> playSong(SongEntity song) {
    _setPlaybackIntent(true);
    _skipInProgress = true;
    return _enqueueQueueMutation((_) async {
      final index = _queue.indexWhere((queued) => queued.id == song.id);
      if (index != -1) {
        await _playAtCore(index);
      } else {
        _preparePlaybackRun();
        await _setQueue([song], initialSong: song);
      }
    });
  }

  @override
  Future<void> play() {
    _setPlaybackIntent(true);
    if (player.playing && !_queueMutationInProgress) return Future.value();

    return _enqueueQueueMutation((_) async {
      if (_queue.isEmpty) {
        _setPlaybackIntent(false);
        return;
      }
      if (_source == null) {
        await _rebuildSourceKeepingPlayback(_lastPosition);
      } else if (player.processingState == ProcessingState.idle) {
        await _loadSource(
          initialIndex: _currentIndex,
          initialPosition: _lastPosition,
        );
      }
    });
  }

  @override
  Future<void> pause() {
    _setPlaybackIntent(false);
    _pendingPlayCountRun = null;
    _activePlaybackRun = null;
    _playbackStartPending = false;
    _lastPosition = player.position;
    return _enqueueQueueMutation((_) async {
      await player.pause();
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          systemActions: {MediaAction.seek},
          androidCompactActionIndices: const [0, 1, 2],
        ),
      );
    });
  }

  @override
  Future<void> stop() {
    _setPlaybackIntent(false);
    _pendingPlayCountRun = null;
    _activePlaybackRun = null;
    _playbackStartPending = false;
    _lastPosition = player.position;
    return _enqueueQueueMutation((_) async {
      await player.stop();
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          controls: [],
          systemActions: {MediaAction.seek},
          androidCompactActionIndices: const [0, 1, 2],
        ),
      );
    });
  }

  @override
  Future<void> onTaskRemoved() => stop();

  @override
  Future<void> seek(Duration position) {
    return _enqueueQueueMutation((_) => player.seek(position));
  }

  @override
  Future<void> skipToNext() {
    _setPlaybackIntent(true);
    _skipInProgress = true;
    return _enqueueQueueMutation((_) async {
      if (_queue.isEmpty) return;
      final next = _currentIndex + 1;
      if (next >= _queue.length) {
        if (_repeatMode != AudioServiceRepeatMode.none) {
          await _playAtCore(0);
        } else {
          await _finishQueueCore(
            _playbackIntentGeneration,
            _autoplayGeneration,
          );
        }
        return;
      }
      await _playAtCore(next);
    });
  }

  @override
  Future<void> skipToPrevious() {
    _setPlaybackIntent(true);
    _skipInProgress = true;
    return _enqueueQueueMutation((_) async {
      if (_queue.isEmpty) return;
      if (player.position.inSeconds > 3) {
        await _playAtCore(_currentIndex);
        return;
      }
      final previous = _currentIndex - 1;
      await _playAtCore(previous >= 0 ? previous : _queue.length - 1);
    });
  }

  @override
  Future<void> skipToQueueItem(int index) {
    _setPlaybackIntent(true);
    _skipInProgress = true;
    return _enqueueQueueMutation((_) => _playAtCore(index));
  }

  Future<void> _finishQueue() {
    // A crossfade owns the handoff when it is already active.
    if (_crossfadeState != _CrossfadeState.idle) return Future.value();
    final intentGeneration = _playbackIntentGeneration;
    final autoplayGeneration = _autoplayGeneration;
    return _enqueueQueueMutation(
      (_) => _finishQueueCore(intentGeneration, autoplayGeneration),
    );
  }

  Future<void> _finishQueueCore(
    int intentGeneration,
    int autoplayGeneration,
  ) async {
    if (intentGeneration != _playbackIntentGeneration) return;
    if (!_autoplayEnabled ||
        !_wantPlaying ||
        autoplayGeneration != _autoplayGeneration) {
      await _completeQueueStopped();
      return;
    }
    if (_queue.isEmpty) return;

    if (_isShuffled) _queue.shuffle();
    _currentIndex = 0;
    _lastPosition = Duration.zero;
    try {
      await _buildSource();
      final source = _source;
      if (source == null) throw StateError('Unable to rebuild queue source');
      _suppressCurrentSongEvents = true;
      try {
        await player.setAudioSource(
          source,
          initialIndex: 0,
          initialPosition: Duration.zero,
          preload: false,
        );
      } finally {
        _suppressCurrentSongEvents = false;
      }
    } catch (error) {
      debugPrint('Failed to prepare autoplay queue: $error');
      if (intentGeneration == _playbackIntentGeneration) {
        await _completeQueueStopped();
      }
      return;
    }

    if (intentGeneration != _playbackIntentGeneration) return;
    if (!_autoplayEnabled ||
        autoplayGeneration != _autoplayGeneration ||
        !_wantPlaying) {
      await _completeQueueStopped();
      return;
    }
    _preparePlaybackRun();
  }

  Future<void> _completeQueueStopped() async {
    _setPlaybackIntent(false);
    _pendingPlayCountRun = null;
    _activePlaybackRun = null;
    _playbackStartPending = false;
    _cancelCrossfadeAndRestore();
    if (player.playing) await player.pause();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.completed,
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        updatePosition: player.duration ?? Duration.zero,
        bufferedPosition: player.bufferedPosition,
        systemActions: {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );
  }

  @visibleForTesting
  Future<void> finishQueueForTesting() => _finishQueue();

  @visibleForTesting
  Future<void> performCrossfadeTransitionForTesting() async {
    if (_queue.length < 2) return;
    _crossfadeState = _CrossfadeState.transitioning;
    await _performTransition((_currentIndex + 1) % _queue.length);
  }

  Future<void> setShuffle(bool enabled) {
    return _enqueueQueueMutation((_) async {
      if (_queue.isEmpty) {
        _isShuffled = enabled;
        _notifyShuffleMode();
        return;
      }

      final current = _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;
      final position = player.processingState == ProcessingState.idle
          ? _lastPosition
          : player.position;

      if (enabled && !_isShuffled) {
        // Capture the original order only on the first shuffle enable.
        if (_orderedQueue.isEmpty) _orderedQueue = List.of(_queue);
        _queue = List.of(_queue)..shuffle();
      } else if (!enabled && _isShuffled && _orderedQueue.isNotEmpty) {
        _queue = List.of(_orderedQueue);
      }
      _isShuffled = enabled;

      var nextIndex = current == null
          ? 0
          : _queue.indexWhere((song) => identical(song, current));
      if (nextIndex < 0 && current != null) {
        nextIndex = _queue.indexWhere((song) => song.id == current.id);
      }
      _currentIndex = nextIndex < 0 ? 0 : nextIndex;

      await _rebuildSourceKeepingPlayback(position);
      _notifyShuffleMode();
    });
  }

  /// Moves the queue entry at [oldIndex] to [newIndex] (onReorderItem
  /// semantics: post-removal insertion index, so no extra adjustment).
  /// Reorders, removals, additions, shuffle, and full replacements all use
  /// the same FIFO, so native source operations cannot interleave.
  Future<void> reorderQueue(int oldIndex, int newIndex) {
    return _enqueueQueueMutation((_) => _doReorderQueue(oldIndex, newIndex));
  }

  /// Where the playing entry at [currentIndex] ends up after moving the
  /// entry at [oldIndex] to [newIndex] (post-removal insertion semantics).
  /// Pure position arithmetic — unlike an id lookup it stays correct when
  /// the same song appears multiple times in the queue.
  @visibleForTesting
  static int adjustIndexAfterMove(
    int currentIndex,
    int oldIndex,
    int newIndex,
  ) {
    if (currentIndex == oldIndex) return newIndex;
    if (oldIndex < currentIndex && currentIndex <= newIndex) {
      return currentIndex - 1;
    }
    if (newIndex <= currentIndex && currentIndex < oldIndex) {
      return currentIndex + 1;
    }
    return currentIndex;
  }

  Future<void> _doReorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;

    final position = player.processingState == ProcessingState.idle
        ? _lastPosition
        : player.position;

    final songs = List<SongEntity>.from(_queue);
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);
    _queue = songs;
    if (!_isShuffled) _orderedQueue = List.of(_queue);

    _currentIndex = adjustIndexAfterMove(
      _currentIndex,
      oldIndex,
      newIndex,
    ).clamp(0, _queue.length - 1);

    await _rebuildSourceKeepingPlayback(
      position,
      moveFrom: oldIndex,
      moveTo: newIndex,
    );
  }

  /// Removes every queue entry whose song id is in [ids]. This shares the
  /// same FIFO as reorder/add/shuffle/replacement operations, so the retained
  /// just_audio source and logical index space cannot diverge.
  ///
  /// Contract: the currently playing song is NOT among [ids] — callers route
  /// current-song removal through [setQueue] instead.
  Future<void> removeQueueItems(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    final doomed = ids.toSet();
    return _enqueueQueueMutation((_) async {
      final removedIndices = <int>[];
      for (var i = 0; i < _queue.length; i++) {
        if (doomed.contains(_queue[i].id)) removedIndices.add(i);
      }
      if (removedIndices.isEmpty) return;

      final position = player.processingState == ProcessingState.idle
          ? _lastPosition
          : player.position;
      final current = _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

      _queue = [
        for (var i = 0; i < _queue.length; i++)
          if (!removedIndices.contains(i)) _queue[i],
      ];
      if (!_isShuffled) {
        _orderedQueue = List.of(_queue);
      } else {
        _orderedQueue.removeWhere((song) => doomed.contains(song.id));
      }

      if (_queue.isEmpty) {
        _setPlaybackIntent(false);
        await _setQueue(const []);
        return;
      }
      if (current != null) {
        var next = _queue.indexWhere((song) => identical(song, current));
        if (next < 0) next = _queue.indexWhere((song) => song.id == current.id);
        _currentIndex = next >= 0 ? next : _queue.length - 1;
      } else {
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
      }

      // An idle player still owns its last native source. Rebuild and install
      // the replacement without preloading or starting it; this prevents the
      // next play() from indexing the stale source.
      final src = _source;
      if (src != null &&
          player.processingState != ProcessingState.idle &&
          src.children.length == _queue.length + removedIndices.length) {
        _suppressCurrentSongEvents = true;
        try {
          for (final index in removedIndices.reversed) {
            await src.removeAt(index);
          }
        } catch (error) {
          debugPrint(
            'In-place queue removal failed, falling back to reload: $error',
          );
          await _rebuildSourceKeepingPlayback(position);
        } finally {
          _suppressCurrentSongEvents = false;
        }
      } else {
        await _rebuildSourceKeepingPlayback(position);
      }
    });
  }

  Future<void> _rebuildSourceKeepingPlayback(
    Duration position, {
    int? moveFrom,
    int? moveTo,
  }) async {
    if (_queue.isEmpty) return;

    // Prefer a gapless in-place reorder of an active source. A stopped
    // just_audio player is idle but still retains the old source, so it must
    // take the explicit rebuild/install path below instead of returning.
    if (player.processingState != ProcessingState.idle) {
      try {
        final src = _source;
        if (src != null && src.children.length == _queue.length) {
          if (moveFrom != null && moveTo != null) {
            await _moveSourceInPlace(moveFrom, moveTo);
          } else {
            await _reorderSourceInPlace(_queue);
          }
          return;
        }
      } catch (error) {
        debugPrint(
          'In-place source reorder failed, falling back to reload: $error',
        );
      }
    }

    await _buildSource();
    final source = _source;
    if (source == null) return;
    _suppressCurrentSongEvents = true;
    try {
      await player.setAudioSource(
        source,
        initialIndex: _currentIndex,
        initialPosition: position,
        preload: _wantPlaying,
      );
    } finally {
      _suppressCurrentSongEvents = false;
    }
  }

  /// Applies a single queue drag to the loaded [ConcatenatingAudioSource]
  /// without stopping playback. [ConcatenatingAudioSource.move] uses the
  /// same post-removal insertion semantics as a list removeAt/insert, so the
  /// same [oldIndex]/[newIndex] apply directly — no id diffing, which also
  /// keeps this correct when the same song appears multiple times in the
  /// queue. While the move runs, mediaItem emissions are suppressed so the
  /// intermediate currentIndex event cannot flicker the Now Playing UI.
  /// Throws on any index mismatch so the caller falls back to a full reload.
  Future<void> _moveSourceInPlace(int oldIndex, int newIndex) async {
    final src = _source;
    if (src == null) return;
    if (oldIndex < 0 ||
        oldIndex >= src.children.length ||
        newIndex < 0 ||
        newIndex >= src.children.length) {
      throw StateError(
        'reorder move ($oldIndex -> $newIndex) out of range '
        'for source of length ${src.children.length}',
      );
    }

    _suppressCurrentSongEvents = true;
    try {
      await src.move(oldIndex, newIndex);
    } finally {
      _suppressCurrentSongEvents = false;
    }
  }

  /// Reorders the loaded [ConcatenatingAudioSource] to match [newOrder]
  /// without stopping playback. Moves are applied from the end backwards so
  /// an earlier move never disturbs items that have already been placed.
  /// While the moves run, mediaItem emissions are suppressed so the
  /// intermediate currentIndex events cannot flicker the Now Playing UI.
  /// Note: matches children by song id, so it must only be used for orders
  /// where every id is unique (e.g. shuffle) — single queue drags use
  /// [_moveSourceInPlace] instead.
  Future<void> _reorderSourceInPlace(List<SongEntity> newOrder) async {
    final src = _source;
    if (src == null) return;

    final currentIds = src.children.map((c) {
      if (c is IndexedAudioSource) {
        final t = c.tag;
        return t is SongEntity ? t.id : null;
      }
      return null;
    }).toList();
    final targetIds = [for (final s in newOrder) s.id];
    if (currentIds.length != targetIds.length) return;

    _suppressCurrentSongEvents = true;
    try {
      for (int i = targetIds.length - 1; i >= 0; i--) {
        final targetId = targetIds[i];
        final cur = currentIds.indexOf(targetId);
        if (cur < 0) return; // order mismatch — let the caller fall back
        if (cur == i) continue;
        await src.move(cur, i);
        currentIds.removeAt(cur);
        currentIds.insert(i, targetId);
      }
    } finally {
      _suppressCurrentSongEvents = false;
    }
  }

  /// Emits metadata only. Play counts are committed separately when the main
  /// player actually starts or genuinely advances to another queue item.
  void _emitCurrentSong() {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    _lastMediaItem = _songToMediaItem(song).copyWith(duration: player.duration);
    mediaItem.add(_lastMediaItem!);
  }

  SongEntity _preferCommittedSong(SongEntity song) {
    final committed = _committedSongMetadata[song.id];
    if (committed != null) return committed.copyWith();
    for (final existing in _queue) {
      if (existing.id == song.id) return existing.copyWith();
    }
    for (final existing in _orderedQueue) {
      if (existing.id == song.id) return existing.copyWith();
    }
    return song.copyWith();
  }

  void applyCommittedSong(SongEntity song) {
    _committedSongMetadata[song.id] = song;
    SongEntity? countedReplacement;
    for (var i = 0; i < _queue.length; i++) {
      final existing = _queue[i];
      if (existing.id != song.id) continue;
      final updated = song.copyWith();
      _queue[i] = updated;
      if (identical(existing, _countedSong)) countedReplacement = updated;
    }
    for (var i = 0; i < _orderedQueue.length; i++) {
      if (_orderedQueue[i].id == song.id) {
        _orderedQueue[i] = song.copyWith();
      }
    }
    if (countedReplacement != null) _countedSong = countedReplacement;
  }

  /// Adds [songs] to the end of the current queue (or right after the current
  /// song when [playNext] is true) without interrupting playback. Songs
  /// already in the queue are skipped. Returns true when at least one song
  /// was actually inserted.
  Future<bool> addToQueue(
    List<SongEntity> songs, {
    bool playNext = false,
  }) async {
    if (songs.isEmpty) return false;

    return _enqueueQueueMutation((_) async {
      if (_queue.isEmpty) {
        _setPlaybackIntent(true);
        _preparePlaybackRun();
        await _setQueue(songs, initialSong: songs.first);
        return true;
      }
      final newSongs = songs
          .where((song) => !_queue.any((queued) => queued.id == song.id))
          .toList();
      if (newSongs.isEmpty) return false;

      final insertIndex = playNext ? _currentIndex + 1 : _queue.length;
      final oldLength = _queue.length;
      final position = player.processingState == ProcessingState.idle
          ? _lastPosition
          : player.position;
      _queue.insertAll(insertIndex, newSongs);
      if (!_isShuffled) {
        _orderedQueue.insertAll(insertIndex, newSongs);
      } else {
        // Preserve the original queue for a later shuffle-off.
        _orderedQueue.addAll(newSongs);
      }

      final src = _source;
      if (src != null &&
          player.processingState != ProcessingState.idle &&
          src.children.length == oldLength) {
        try {
          await src.insertAll(insertIndex, [
            for (final song in newSongs) _songToAudioSource(song),
          ]);
          return true;
        } catch (error) {
          debugPrint('Queue insert failed, falling back to reload: $error');
        }
      }
      await _rebuildSourceKeepingPlayback(position);
      return true;
    });
  }

  void _notifyShuffleMode() {
    playbackState.add(
      playbackState.value.copyWith(
        shuffleMode: _isShuffled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        systemActions: {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await player.setLoopMode(_mapRepeatMode(repeatMode));
    playbackState.add(
      playbackState.value.copyWith(
        repeatMode: repeatMode,
        systemActions: {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );
  }

  MediaItem _songToMediaItem(SongEntity song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(
        milliseconds: song.durationMs > 0 ? song.durationMs : 1,
      ),
      artUri: song.coverArtPath != null && song.coverArtPath!.isNotEmpty
          ? Uri.file(song.coverArtPath!)
          : null,
    );
  }

  AudioSource _songToAudioSource(SongEntity song) {
    final candidates = <String>[
      if (song.realPath != null &&
          song.realPath!.isNotEmpty &&
          song.realPath != song.filePath)
        song.realPath!,
      song.filePath,
    ];
    for (final candidate in candidates) {
      if (candidate.startsWith('content://') ||
          candidate.startsWith('http://') ||
          candidate.startsWith('https://')) {
        return AudioSource.uri(Uri.parse(candidate), tag: song);
      }
      if (File(candidate).existsSync()) {
        return AudioSource.file(candidate, tag: song);
      }
    }
    return AudioSource.file(song.filePath, tag: song);
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  LoopMode _mapRepeatMode(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.none:
        return LoopMode.off;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        return LoopMode.all;
    }
  }

  SongEntity? get currentSong =>
      _queue.isNotEmpty && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;

  void dispose() {
    _crossfadeTimer?.cancel();
    _fadeOutTimer?.cancel();
    _playerStateSub?.cancel();
    _processingStateSub?.cancel();
    _currentIndexSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _positionDiscontinuitySub?.cancel();
    player.dispose();
    _crossfadePlayer.dispose();
  }
}
