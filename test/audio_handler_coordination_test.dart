import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/services/background_audio_service.dart';
import 'package:celsius/services/widget_service.dart';

class _RecordingWidgetService implements WidgetService {
  final List<SongEntity> songs = [];
  final List<bool> playStates = [];
  int clearCount = 0;

  @override
  Function()? onNext;
  @override
  Function()? onPlayPause;
  @override
  Function()? onPrevious;

  @override
  Future<void> updateWidget({
    required String title,
    required String artist,
    required bool isPlaying,
    String? artPath,
  }) async {}

  @override
  void init() {}

  @override
  void dispose() {}

  @override
  void onPlayStateChanged(bool isPlaying) {
    playStates.add(isPlaying);
  }

  @override
  void onSongChanged(SongEntity song, bool isPlaying) {
    songs.add(song);
  }

  @override
  void onSongCleared() {
    clearCount++;
  }
}

class _ControlledAudioPlayer extends AudioPlayer {
  final List<String> calls = [];
  final positionController = StreamController<Duration>.broadcast(sync: true);
  final playerStateController = StreamController<PlayerState>.broadcast(
    sync: true,
  );
  final currentIndexController = StreamController<int?>.broadcast(sync: true);
  Completer<Duration?>? sourceGate;
  bool failNextSource = false;
  bool failNextSeek = false;
  bool failNextStop = false;
  Completer<void>? nextPlayGate;
  Object? nextPlayError;
  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  Duration _position = Duration.zero;

  int get sourceCalls => calls.where((call) => call == 'source').length;
  int get playCalls => calls.where((call) => call == 'play').length;
  int get seekCalls => calls.where((call) => call == 'seek').length;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _processingState;

  @override
  Duration? get duration => const Duration(minutes: 3);

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => positionController.stream;

  @override
  Stream<PlayerState> get playerStateStream => playerStateController.stream;

  @override
  Stream<int?> get currentIndexStream => currentIndexController.stream;

  void emitState({
    required bool playing,
    ProcessingState processing = ProcessingState.ready,
  }) {
    _playing = playing;
    _processingState = processing;
    playerStateController.add(PlayerState(playing, processing));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    calls.add('source');
    if (failNextSource) {
      failNextSource = false;
      throw StateError('source failed');
    }
    final gate = sourceGate;
    if (gate != null) await gate.future;
    _processingState = ProcessingState.ready;
    playerStateController.add(PlayerState(false, ProcessingState.ready));
    if (initialIndex != null) currentIndexController.add(initialIndex);
    return null;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _playing = true;
    playerStateController.add(PlayerState(true, ProcessingState.ready));
    final gate = nextPlayGate;
    final error = nextPlayError;
    nextPlayGate = null;
    nextPlayError = null;
    if (gate != null) await gate.future;
    if (error != null) throw error;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing = false;
    playerStateController.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (failNextStop) {
      failNextStop = false;
      throw StateError('stop failed');
    }
    _playing = false;
    _processingState = ProcessingState.idle;
    playerStateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    calls.add('seek');
    if (failNextSeek) {
      failNextSeek = false;
      throw StateError('seek failed');
    }
    if (position != null) _position = position;
    if (index != null) currentIndexController.add(index);
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume');
  }

  void setPosition(Duration value) {
    _position = value;
    positionController.add(value);
  }

  void emitIndex(int index) {
    currentIndexController.add(index);
  }

  void markIdle() {
    emitState(playing: false, processing: ProcessingState.idle);
  }

  void markCompleted() {
    _playing = false;
    _processingState = ProcessingState.completed;
    playerStateController.add(PlayerState(false, ProcessingState.completed));
  }

  @override
  Future<void> dispose() async {
    await positionController.close();
    await playerStateController.close();
    await currentIndexController.close();
    await super.dispose();
  }
}

SongEntity _song(String id) =>
    SongEntity(id: id, title: 'Title $id', filePath: '/music/$id.mp3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('play and seek wait behind a loading source replacement', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;

    final setQueue = handler.setQueue([_song('A')], playWhenReady: false);
    await Future<void>.delayed(Duration.zero);
    final play = handler.play();
    final seek = handler.seek(const Duration(seconds: 12));
    await Future<void>.delayed(Duration.zero);

    expect(mainPlayer.sourceCalls, 1);
    expect(mainPlayer.playCalls, 0);
    expect(mainPlayer.seekCalls, 0);

    gate.complete(null);
    await Future.wait([setQueue, play, seek]);

    final sourceIndex = mainPlayer.calls.indexOf('source');
    expect(sourceIndex, lessThan(mainPlayer.calls.indexOf('play')));
    expect(sourceIndex, lessThan(mainPlayer.calls.indexOf('seek')));
  });

  test('previous-track restart is serialized behind source loading', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;

    final setQueue = handler.setQueue([_song('A')], playWhenReady: false);
    await Future<void>.delayed(Duration.zero);
    mainPlayer.setPosition(const Duration(seconds: 5));
    final previous = handler.skipToPrevious();
    await Future<void>.delayed(Duration.zero);

    expect(mainPlayer.seekCalls, 0);
    gate.complete(null);
    await setQueue;
    await previous;

    expect(mainPlayer.calls, containsAllInOrder(['source', 'seek', 'play']));
  });

  test('queue-index command validates against the replacement queue', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    await handler.setQueue([_song('A'), _song('B')], playWhenReady: false);
    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;

    final replacement = handler.setQueue([
      _song('C'),
      _song('D'),
      _song('E'),
      _song('F'),
      _song('G'),
      _song('H'),
    ], playWhenReady: false);
    final selectLast = handler.skipToQueueItem(5);
    gate.complete(null);
    await Future.wait([replacement, selectLast]);

    expect(handler.currentIndex, 5);
    expect(handler.currentSong?.id, 'H');
  });

  test('adding to an empty queue waits for a pending replacement', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;

    final replacement = handler.setQueue([
      _song('A'),
      _song('B'),
    ], playWhenReady: false);
    final added = handler.addToQueue([_song('C')]);
    gate.complete(null);
    await Future.wait([replacement, added]);

    expect(handler.songs.map((song) => song.id), ['A', 'B', 'C']);
  });

  test('stale playback-start failure does not cancel a newer queue', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    final oldPlayGate = Completer<void>();
    mainPlayer.nextPlayGate = oldPlayGate;
    mainPlayer.nextPlayError = StateError('old playback failed');

    await handler.setQueue([_song('A')]);
    await Future<void>.delayed(Duration.zero);
    expect(mainPlayer.playCalls, 1);
    final newer = handler.setQueue([_song('B')]);
    oldPlayGate.complete();
    await newer;
    await Future<void>.delayed(Duration.zero);

    expect(handler.wantsPlayback, isTrue);
    expect(handler.currentSong?.id, 'B');
  });

  test('native auto-advance is counted once after position advances', () async {
    final recorded = <String>[];
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
      playCountRecorder: (song) async => recorded.add(song.id),
    );
    addTearDown(handler.dispose);
    await handler.setQueue([_song('A'), _song('B')], playWhenReady: false);
    await Future<void>.delayed(Duration.zero);

    mainPlayer.emitState(playing: true);
    mainPlayer.emitIndex(1);
    await Future<void>.delayed(Duration.zero);
    expect(recorded, isEmpty);

    mainPlayer.setPosition(const Duration(seconds: 1));
    mainPlayer.setPosition(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    expect(recorded, ['B']);
  });

  test(
    'failed playback start is not counted before position advances',
    () async {
      final mainPlayer = _ControlledAudioPlayer()
        ..nextPlayError = StateError('playback failed');
      final handler = AudioPlayerHandler(
        initialSettings: const AppSettings(),
        mainPlayer: mainPlayer,
        crossfadePlayer: _ControlledAudioPlayer(),
      );
      addTearDown(handler.dispose);

      await handler.setQueue([_song('A')]);
      await Future<void>.delayed(Duration.zero);

      expect(handler.hasCommittedPlaybackRunForTesting, isFalse);
    },
  );

  test('failed source mutation is repaired before surfacing failure', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    mainPlayer.failNextSource = true;

    await expectLater(
      handler.setQueue([_song('A')], playWhenReady: false),
      throwsStateError,
    );

    expect(handler.songs.map((song) => song.id), ['A']);
    expect(handler.sourceSongIds, ['A']);
  });

  test(
    'deletion invalidates an in-flight provider queue replacement',
    () async {
      final mainPlayer = _ControlledAudioPlayer();
      final handler = AudioPlayerHandler(
        initialSettings: const AppSettings(),
        mainPlayer: mainPlayer,
        crossfadePlayer: _ControlledAudioPlayer(),
      );
      final notifier = AudioPlayerNotifier(
        widgetService: _RecordingWidgetService(),
        initialSettings: const AppSettings(),
      );
      notifier.setHandler(handler);
      addTearDown(notifier.dispose);
      addTearDown(handler.dispose);

      final gate = Completer<Duration?>();
      mainPlayer.sourceGate = gate;
      final playing = notifier.playSong(_song('A'), [_song('A')]);
      await Future<void>.delayed(Duration.zero);
      final removal = notifier.handleSongsRemoved(const ['A']);
      gate.complete(null);
      await Future.wait([playing, removal]);

      expect(handler.songs, isEmpty);
      expect(notifier.state.currentSong, isNull);
      expect(notifier.state.queue, isEmpty);
    },
  );

  test(
    'newer playSong supersedes older queued mutations without drift',
    () async {
      final mainPlayer = _ControlledAudioPlayer();
      final handler = AudioPlayerHandler(
        initialSettings: const AppSettings(),
        mainPlayer: mainPlayer,
        crossfadePlayer: _ControlledAudioPlayer(),
      );
      final notifier = AudioPlayerNotifier(
        widgetService: _RecordingWidgetService(),
        initialSettings: const AppSettings(),
      );
      notifier.setHandler(handler);
      addTearDown(notifier.dispose);
      addTearDown(handler.dispose);

      final gate = Completer<Duration?>();
      mainPlayer.sourceGate = gate;
      final oldPlay = notifier.playSong(_song('A'), [
        _song('A'),
        _song('B'),
        _song('C'),
      ]);
      await Future<void>.delayed(Duration.zero);
      final olderAdd = notifier.addToQueue(_song('D'));
      notifier.reorderQueue(0, 2);
      final olderShuffle = notifier.setShuffle(true);
      final newerPlay = notifier.playSong(_song('B'), [_song('B')]);
      gate.complete(null);
      await Future.wait([oldPlay, olderAdd, olderShuffle, newerPlay]);

      expect(handler.songs.map((song) => song.id), ['B']);
      expect(notifier.state.currentSong?.id, 'B');
      expect(notifier.state.queue.map((song) => song.id), ['B']);
    },
  );

  test('deletion filters a non-current song from an in-flight queue', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    final notifier = AudioPlayerNotifier(
      widgetService: _RecordingWidgetService(),
      initialSettings: const AppSettings(),
    );
    notifier.setHandler(handler);
    addTearDown(notifier.dispose);
    addTearDown(handler.dispose);

    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;
    final playing = notifier.playSong(_song('A'), [_song('A'), _song('B')]);
    await Future<void>.delayed(Duration.zero);
    final adding = notifier.addToQueue(_song('C'));
    final removal = notifier.handleSongsRemoved(const ['B']);
    gate.complete(null);
    await Future.wait([playing, adding, removal]);

    expect(handler.songs.map((song) => song.id), ['A', 'C']);
    expect(notifier.state.queue.map((song) => song.id), ['A', 'C']);
  });

  test('widget follows native queue and play-state progression', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    final widgetService = _RecordingWidgetService();
    final notifier = AudioPlayerNotifier(
      widgetService: widgetService,
      initialSettings: const AppSettings(),
    );
    notifier.setHandler(handler);
    addTearDown(notifier.dispose);
    addTearDown(handler.dispose);

    await notifier.playSong(_song('A'), [_song('A')]);
    await notifier.addToQueue(_song('B'));
    widgetService.songs.clear();
    widgetService.playStates.clear();

    mainPlayer.emitState(playing: true);
    mainPlayer.emitIndex(1);
    await Future<void>.delayed(Duration.zero);

    expect(widgetService.songs.last.title, 'Title B');
    expect(widgetService.playStates, contains(true));
  });

  test('provider resynchronizes a repaired queue insertion', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    final notifier = AudioPlayerNotifier(
      widgetService: _RecordingWidgetService(),
      initialSettings: const AppSettings(),
    );
    notifier.setHandler(handler);
    addTearDown(notifier.dispose);
    addTearDown(handler.dispose);

    await notifier.playSong(_song('A'), [_song('A')]);
    mainPlayer.markIdle();
    mainPlayer.failNextSource = true;
    await expectLater(notifier.addToQueue(_song('B')), throwsStateError);

    expect(handler.songs.map((song) => song.id), ['A', 'B']);
    expect(notifier.state.queue.map((song) => song.id), ['A', 'B']);
  });

  test('committed metadata updates an in-flight queue and handler', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    final notifier = AudioPlayerNotifier(
      widgetService: _RecordingWidgetService(),
      initialSettings: const AppSettings(),
    );
    notifier.setHandler(handler);
    addTearDown(notifier.dispose);
    addTearDown(handler.dispose);

    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;
    final playing = notifier.playSong(_song('A'), [_song('A')]);
    await Future<void>.delayed(Duration.zero);
    notifier.applyCommittedSong(_song('A').copyWith(isFavorite: true));
    gate.complete(null);
    await playing;

    expect(handler.songs.single.isFavorite, isTrue);
    expect(notifier.state.currentSong?.isFavorite, isTrue);
    expect(notifier.state.queue.single.isFavorite, isTrue);
  });

  test(
    'stale queue completion does not stop a newer playback intent',
    () async {
      final mainPlayer = _ControlledAudioPlayer();
      final handler = AudioPlayerHandler(
        initialSettings: const AppSettings(autoplayEnabled: true),
        mainPlayer: mainPlayer,
        crossfadePlayer: _ControlledAudioPlayer(),
      );
      addTearDown(handler.dispose);
      await handler.setQueue([_song('A')]);
      mainPlayer.markCompleted();

      final gate = Completer<Duration?>();
      mainPlayer.sourceGate = gate;
      final finishing = handler.finishQueueForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(mainPlayer.sourceCalls, 2);

      final replacement = handler.setQueue([_song('B')]);
      gate.complete(null);
      await Future.wait([finishing, replacement]);
      await Future<void>.delayed(Duration.zero);

      expect(handler.wantsPlayback, isTrue);
      expect(handler.currentSong?.id, 'B');
      expect(mainPlayer.playCalls, 2);
    },
  );

  test('crossfade transition counts only after main-player progress', () async {
    final recorded = <String>[];
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(crossfadeEnabled: true),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
      playCountRecorder: (song) async => recorded.add(song.id),
    );
    addTearDown(handler.dispose);
    await handler.setQueue([_song('A'), _song('B')]);
    await Future<void>.delayed(Duration.zero);

    await handler.performCrossfadeTransitionForTesting();
    expect(recorded, isEmpty);
    expect(handler.isPlaybackStartPendingForTesting, isTrue);
    expect(handler.pendingPlaybackRunForTesting, isNotNull);
    mainPlayer.setPosition(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(recorded, ['B']);
  });

  test(
    'crossfade stop failure pauses the auxiliary player before recovery',
    () async {
      final mainPlayer = _ControlledAudioPlayer();
      final crossfadePlayer = _ControlledAudioPlayer()..failNextStop = true;
      final handler = AudioPlayerHandler(
        initialSettings: const AppSettings(
          crossfadeEnabled: true,
          autoplayEnabled: false,
        ),
        mainPlayer: mainPlayer,
        crossfadePlayer: crossfadePlayer,
      );
      addTearDown(handler.dispose);
      await handler.setQueue([_song('A'), _song('B')]);

      await handler.performCrossfadeTransitionForTesting();

      expect(crossfadePlayer.playing, isFalse);
      expect(mainPlayer.seekCalls, 0);
      expect(mainPlayer.sourceCalls, 2);
    },
  );

  test(
    'crossfade seek failure rebuilds a usable source without autoplay',
    () async {
      final mainPlayer = _ControlledAudioPlayer()..failNextSeek = true;
      final handler = AudioPlayerHandler(
        initialSettings: const AppSettings(autoplayEnabled: false),
        mainPlayer: mainPlayer,
        crossfadePlayer: _ControlledAudioPlayer(),
      );
      addTearDown(handler.dispose);
      await handler.setQueue([_song('A'), _song('B')]);

      await handler.performCrossfadeTransitionForTesting();
      expect(mainPlayer.sourceCalls, 2);
      expect(handler.sourceSongIds, ['A', 'B']);

      await handler.play();
      expect(mainPlayer.playCalls, 1);
    },
  );

  test('crossfade-only setting changes do not invalidate autoplay', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(autoplayEnabled: true),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    await handler.setQueue([_song('A')]);
    final playCountBeforeFinish = mainPlayer.playCalls;
    mainPlayer.markCompleted();
    mainPlayer.sourceGate = Completer<Duration?>();
    final finishing = handler.finishQueueForTesting();
    await Future<void>.delayed(Duration.zero);

    handler.updateRuntimeSettings(
      const AppSettings(
        autoplayEnabled: true,
        crossfadeEnabled: true,
        crossfadeDurationMs: 800,
      ),
    );
    mainPlayer.sourceGate!.complete(null);
    await finishing;
    await Future<void>.delayed(Duration.zero);

    expect(mainPlayer.playCalls, playCountBeforeFinish + 1);
    expect(handler.wantsPlayback, isTrue);
  });

  test('disabling autoplay invalidates a queued end transition', () async {
    final mainPlayer = _ControlledAudioPlayer();
    final handler = AudioPlayerHandler(
      initialSettings: const AppSettings(autoplayEnabled: true),
      mainPlayer: mainPlayer,
      crossfadePlayer: _ControlledAudioPlayer(),
    );
    addTearDown(handler.dispose);
    await handler.setQueue([_song('A')]);
    final playCountBeforeFinish = mainPlayer.playCalls;
    mainPlayer.markCompleted();

    final gate = Completer<Duration?>();
    mainPlayer.sourceGate = gate;
    final finishing = handler.finishQueueForTesting();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(mainPlayer.sourceCalls, 2);

    handler.updateRuntimeSettings(const AppSettings(autoplayEnabled: false));
    gate.complete(null);
    await finishing;
    await Future<void>.delayed(Duration.zero);

    expect(mainPlayer.playCalls, playCountBeforeFinish);
    expect(handler.wantsPlayback, isFalse);
  });
}
