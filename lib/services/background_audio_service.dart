import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

class AudioPlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  late final AudioPlayer player;
  List<SongEntity> _queue = [];
  List<SongEntity> _orderedQueue = [];
  int _currentIndex = 0;
  bool _isShuffled = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  MediaItem? _lastMediaItem;
  bool _wantPlaying = false;
  ConcatenatingAudioSource? _source;
  Duration _lastPosition = Duration.zero;
  int _queueSetSeq = 0;
  /// Index of the last song whose play count was recorded. Guards against
  /// double counting when the same index is re-emitted (e.g. after a
  /// shuffle/reorder rebuild that keeps the current song).
  int _countedIndex = -1;
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

  AudioPlayerHandler() {
    try {
      player = AudioPlayer();
    } catch (e) {
      debugPrint('Failed to initialize AudioPlayer: $e');
      rethrow;
    }

    playbackState.add(PlaybackState(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
    ));

    _positionSub = player.positionStream.listen((pos) {
      try {
        playbackState.add(playbackState.value.copyWith(
          updatePosition: pos,
          systemActions: {MediaAction.seek},
        ));
      } catch (e) {
        debugPrint('Position stream error: $e');
      }
    }, onError: (Object e) {
      debugPrint('Position stream error: $e');
    });

    _durationSub = player.durationStream.listen((duration) {
      try {
        final item = _lastMediaItem;
        if (item == null || duration == null || duration <= Duration.zero) return;
        if (item.duration == duration) return;
        if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
        if (_queue[_currentIndex].id != item.id) return;
        _lastMediaItem = item.copyWith(duration: duration);
        mediaItem.add(_lastMediaItem!);
      } catch (e) {
        debugPrint('Duration stream error: $e');
      }
    }, onError: (Object e) {
      debugPrint('Duration stream error: $e');
    });

    _currentIndexSub = player.currentIndexStream.listen((index) {
      try {
        if (index == null || index < 0 || index >= _queue.length) return;
        _currentIndex = index;
        if (!_suppressCurrentSongEvents) {
          _emitCurrentSong();
        }
        playbackState.add(playbackState.value.copyWith(
          queueIndex: index,
          systemActions: {MediaAction.seek},
          androidCompactActionIndices: const [0, 1, 2],
        ));
      } catch (e) {
        debugPrint('Current index stream error: $e');
      }
    }, onError: (Object e) {
      debugPrint('Current index stream error: $e');
    });

    _playerStateSub = player.playerStateStream.listen((state) {
      try {
        final processingState = _mapProcessingState(state.processingState);
        playbackState.add(playbackState.value.copyWith(
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
        ));
      } catch (e) {
        debugPrint('Player state stream error: $e');
      }
    }, onError: (Object e) {
      debugPrint('Player state stream error: $e');
    });

    _processingStateSub = player.processingStateStream.listen((state) {
      try {
        if (state == ProcessingState.completed) {
          _finishQueue();
        }
      } catch (e) {
        debugPrint('Processing state stream error: $e');
      }
    }, onError: (Object e) {
      debugPrint('Processing state stream error: $e');
    });
  }

  Duration get position => player.position;
  Duration get duration => player.duration ?? Duration.zero;
  bool get isPlaying => player.playing;
  int get currentIndex => _currentIndex;
  List<SongEntity> get songs => _queue;
  bool get isShuffled => _isShuffled;
  AudioServiceRepeatMode get currentRepeatMode => _repeatMode;

  void setVolume(double volume) {
    player.setVolume(volume);
  }

  Future<void> _buildSource() async {
    if (_queue.isEmpty) return;
    _source = ConcatenatingAudioSource(
      children: [for (final song in _queue) _songToAudioSource(song)],
    );
  }

  Future<void> setQueue(List<SongEntity> songs, {SongEntity? initialSong}) async {
    // Bump the generation counter so any in-flight setQueue() knows it is stale.
    final seq = ++_queueSetSeq;

    if (songs.isEmpty) {
      _queue = [];
      _currentIndex = 0;
      queue.add(const []);
      await player.stop();
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        systemActions: {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
      ));
      return;
    }

    _queue = List.of(songs);
    if (_isShuffled) {
      _queue.shuffle();
    }
    _orderedQueue = List.of(songs);
    // A new queue invalidates the play-count guard: the first song of this
    // queue must be counted even if it lands on the previously counted index.
    _countedIndex = -1;
    await _buildSource();

    var startIndex = 0;
    if (initialSong != null) {
      startIndex = _queue.indexWhere((s) => s.id == initialSong.id);
      if (startIndex == -1) startIndex = 0;
    }
    _currentIndex = startIndex;
    queue.add(_queue.map(_songToMediaItem).toList());

    if (_source == null) return;

    _wantPlaying = true;
    await player.setAudioSource(_source!, initialIndex: startIndex, initialPosition: Duration.zero);

    await Future.delayed(const Duration(milliseconds: 50));

    // A newer setQueue() started while we were loading — let it handle playback.
    if (seq != _queueSetSeq) return;

    if (_wantPlaying) {
      await player.play();
    }
  }

  Future<void> _loadSource({
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    if (_source == null || _queue.isEmpty) return;
    _wantPlaying = true;
    await player.setAudioSource(_source!,
        initialIndex: initialIndex, initialPosition: initialPosition);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;

    _currentIndex = index;
    final song = _queue[index];
    final mediaItem = _songToMediaItem(song);
    _lastMediaItem = mediaItem;
    this.mediaItem.add(mediaItem);

    // If the source is already loaded, jump to the item in place with
    // player.seek() — no pause, no source teardown, no audible gap.
    if (player.processingState != ProcessingState.idle && _source != null) {
      await player.seek(Duration.zero, index: index);
      if (_wantPlaying) {
        await player.play();
      }
      return;
    }

    final wasPlaying = player.playing;
    if (wasPlaying) await player.pause();

    try {
      await _loadSource(initialIndex: index, initialPosition: Duration.zero);
    } catch (e) {
      if (wasPlaying) await player.play();
      rethrow;
    }

    if (_wantPlaying) {
      await player.play();
    } else if (!wasPlaying) {
      await player.pause();
    }
  }

  Future<void> playSong(SongEntity song) async {
    if (player.processingState == ProcessingState.idle) {
      final index = _queue.indexWhere((s) => s.id == song.id);
      if (index != -1) {
        await _playAt(index);
      } else {
        await setQueue([song], initialSong: song);
      }
      return;
    }
    
    _wantPlaying = true;
    final index = _queue.indexWhere((s) => s.id == song.id);
    if (index != -1 && index != _currentIndex) {
      await _playAt(index);
    }
  }

  @override
  Future<void> play() async {
    _wantPlaying = true;
    if (_queue.isEmpty) return;

    if (player.processingState == ProcessingState.idle) {
      await _loadSource(
        initialIndex: _currentIndex,
        initialPosition: _lastPosition,
      );
    }
    await player.play();
  }

  @override
  Future<void> pause() async {
    _wantPlaying = false;
    _lastPosition = player.position;
    await player.pause();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      systemActions: {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  @override
  Future<void> stop() async {
    _wantPlaying = false;
    _lastPosition = player.position;
    await player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      controls: [],
      systemActions: {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  @override
  Future<void> onTaskRemoved() async {
    _wantPlaying = false;
    _lastPosition = player.position;
    await player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      controls: [],
      systemActions: {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;

    final next = _currentIndex + 1;
    if (next >= _queue.length) {
      // At the end of the queue: wrap around when repeat is on, otherwise
      // finish the queue (playback stops; the user can press play to restart).
      if (_repeatMode != AudioServiceRepeatMode.none) {
        await _playAt(0);
      } else {
        await _finishQueue();
      }
      return;
    }
    await _playAt(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }
    
    final prev = _currentIndex - 1;
    if (prev >= 0) {
      await _playAt(prev);
    } else {
      await _playAt(_queue.length - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _playAt(index);
  }

  Future<void> _finishQueue() async {
    final autoplayEnabled = HiveStorage.getSettings().autoplayEnabled;

    if (autoplayEnabled) {
      // Restart from the beginning, preserving shuffle state.
      _wantPlaying = true;
      if (_isShuffled) {
        _queue.shuffle();
        queue.add(_queue.map(_songToMediaItem).toList());
      }
      await _buildSource();
      if (_source == null) {
        // Source failed to rebuild — fall through to stopping.
        _wantPlaying = false;
        if (player.playing) await player.pause();
        playbackState.add(playbackState.value.copyWith(
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
        ));
        return;
      }
      await player.setAudioSource(_source!, initialIndex: 0, initialPosition: Duration.zero);
      await player.play();
      _emitCurrentSong();
      return;
    }

    // Make the actual player state match the emitted "completed" state.
    // Natural queue end already has the player stopped; a manual next-at-end
    // would otherwise keep audio playing behind a "stopped" notification.
    _wantPlaying = false;
    if (player.playing) {
      await player.pause();
    }
    playbackState.add(playbackState.value.copyWith(
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
    ));
  }

  Future<void> setShuffle(bool enabled) async {
    if (_queue.isEmpty) {
      _isShuffled = enabled;
      _notifyShuffleMode();
      return;
    }

    final wasPlaying = player.playing;
    final currentId = _currentIndex >= 0 && _currentIndex < _queue.length
        ? _queue[_currentIndex].id
        : null;
    final currentPosition = player.position;

    if (enabled && !_isShuffled) {
      _orderedQueue = List.of(_queue);
      _queue = List.of(_queue)..shuffle();
    } else if (!enabled && _isShuffled) {
      if (_orderedQueue.isNotEmpty) {
        _queue = List.of(_orderedQueue);
      }
    }
    _isShuffled = enabled;

    _currentIndex = currentId == null
        ? 0
        : _queue.indexWhere((s) => s.id == currentId);
    if (_currentIndex < 0) _currentIndex = 0;

    // Reorder the loaded source in place (gapless) and let the reorder
    // suppression handle the intermediate index events without flicker.
    await _rebuildSourceKeepingPlayback(wasPlaying, currentPosition);
    // Re-emit the queue so the system UI (and any queue listeners) see the
    // new order even when the current song did not change.
    queue.add(_queue.map(_songToMediaItem).toList());
    _notifyShuffleMode();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;

    final wasPlaying = player.playing;
    final currentId = _currentIndex >= 0 && _currentIndex < _queue.length
        ? _queue[_currentIndex].id
        : null;
    final currentPosition = player.position;

    final songs = List<SongEntity>.from(_queue);
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);
    _queue = songs;
    if (!_isShuffled) _orderedQueue = List.of(_queue);

    _currentIndex = currentId == null
        ? 0
        : _queue.indexWhere((s) => s.id == currentId);
    if (_currentIndex < 0) _currentIndex = 0;

    await _rebuildSourceKeepingPlayback(wasPlaying, currentPosition);
    queue.add(_queue.map(_songToMediaItem).toList());
  }

  Future<void> _rebuildSourceKeepingPlayback(bool wasPlaying, Duration position) async {
    if (_source == null || _queue.isEmpty) return;
    if (player.processingState == ProcessingState.idle) return;

    // Prefer a gapless in-place reorder of the already-loaded source so
    // playback isn't interrupted. Falls back to a full reload on any mismatch.
    try {
      final src = _source!;
      if (src.children.length == _queue.length) {
        await _reorderSourceInPlace(_queue);
        if (wasPlaying) {
          await player.play();
        }
        return;
      }
    } catch (e) {
      debugPrint('In-place source reorder failed, falling back to reload: $e');
    }

    // Fallback: rebuild the source from the current queue order and reload.
    await _buildSource();
    if (_source == null) return;
    await player.setAudioSource(
      _source!,
      initialIndex: _currentIndex,
      initialPosition: position,
    );
    if (wasPlaying) {
      await player.play();
    }
  }

  /// Reorders the loaded [ConcatenatingAudioSource] to match [newOrder]
  /// without stopping playback. Moves are applied from the end backwards so
  /// an earlier move never disturbs items that have already been placed.
  /// While the moves run, mediaItem emissions are suppressed so the
  /// intermediate currentIndex events cannot flicker the Now Playing UI.
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
      // The final index event may have been suppressed mid-reorder — emit
      // the settled current song so the UI always ends on the correct one.
      _emitCurrentSong();
    }
  }

  /// Emits the song at [_currentIndex] to the mediaItem stream and records a
  /// play. Called on every (non-suppressed) index change and once after an
  /// in-place source reorder has settled.
  void _emitCurrentSong() {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    _lastMediaItem = _songToMediaItem(song).copyWith(duration: player.duration);
    mediaItem.add(_lastMediaItem!);
    // Count each play once, when the song becomes current (covers
    // initial play, manual skips and auto-advance alike).
    if (_currentIndex != _countedIndex) {
      _countedIndex = _currentIndex;
      unawaited(HiveStorage.incrementPlayCount(song.id).catchError((Object e) {
        debugPrint('Failed to increment play count for ${song.id}: $e');
      }));
    }
  }

  /// Adds [songs] to the end of the current queue (or right after the current
  /// song when [playNext] is true) without interrupting playback. Songs
  /// already in the queue are skipped.
  Future<void> addToQueue(List<SongEntity> songs, {bool playNext = false}) async {
    if (songs.isEmpty) return;
    if (_queue.isEmpty) {
      await setQueue(songs);
      return;
    }

    final newSongs = songs.where((s) => !_queue.any((e) => e.id == s.id)).toList();
    if (newSongs.isEmpty) return;

    final insertIndex = playNext ? _currentIndex + 1 : _queue.length;
    _queue.insertAll(insertIndex, newSongs);
    if (!_isShuffled) {
      _orderedQueue.insertAll(insertIndex, newSongs);
    } else {
      // Keep the songs when shuffle is later turned off.
      _orderedQueue.addAll(newSongs);
    }

    final src = _source;
    if (src != null && player.processingState != ProcessingState.idle) {
      try {
        // Gapless: insert the new items into the loaded source at the same
        // position. Inserting at/after the current index does not disturb
        // the currently playing item.
        await src.insertAll(
          insertIndex,
          [for (final s in newSongs) _songToAudioSource(s)],
        );
        queue.add(_queue.map(_songToMediaItem).toList());
        return;
      } catch (e) {
        debugPrint('Queue insert failed, falling back to reload: $e');
      }
    }

    // Fallback: full reload with the updated queue.
    await _buildSource();
    if (_source == null) return;
    await player.setAudioSource(
      _source!,
      initialIndex: _currentIndex,
      initialPosition: player.position,
    );
    queue.add(_queue.map(_songToMediaItem).toList());
  }

  void _notifyShuffleMode() {
    playbackState.add(playbackState.value.copyWith(
      shuffleMode: _isShuffled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      systemActions: {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeatMode = repeatMode;
    await player.setLoopMode(_mapRepeatMode(repeatMode));
    playbackState.add(playbackState.value.copyWith(
      repeatMode: repeatMode,
      systemActions: {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
    ));
  }

  MediaItem _songToMediaItem(SongEntity song) {
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs > 0 ? song.durationMs : 1),
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
    _playerStateSub?.cancel();
    _processingStateSub?.cancel();
    _currentIndexSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    player.dispose();
  }
}