import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/presentation/screens/now_playing/queue_screen.dart';
import 'package:celsius/presentation/themes/now_playing_theme_spec.dart';
import 'package:celsius/services/background_audio_service.dart';

SongEntity _song(String id, [String? title]) =>
    SongEntity(id: id, title: title ?? 'Title $id', filePath: '/music/$id.mp3');

List<String> _ids(List<SongEntity> songs) => [for (final s in songs) s.id];

class _FakeAudioPlayerHandler extends AudioPlayerHandler {
  _FakeAudioPlayerHandler() : super(initialSettings: const AppSettings());

  @override
  List<SongEntity> songs = [];

  @override
  bool wantsPlayback = false;

  bool? lastPlayWhenReady;
  Completer<void>? nextSetQueueGate;
  Object? nextSetQueueError;
  bool nextAddResult = true;

  @override
  void updateRuntimeSettings(AppSettings settings) {}

  @override
  void applyCommittedSong(SongEntity song) {
    songs = [
      for (final queued in songs)
        if (queued.id == song.id) song.copyWith() else queued,
    ];
  }

  @override
  Future<void> setQueue(
    List<SongEntity> nextSongs, {
    SongEntity? initialSong,
    bool playWhenReady = true,
  }) async {
    songs = List.of(nextSongs);
    wantsPlayback = nextSongs.isNotEmpty && playWhenReady;
    lastPlayWhenReady = playWhenReady;
    final gate = nextSetQueueGate;
    final error = nextSetQueueError;
    nextSetQueueGate = null;
    nextSetQueueError = null;
    if (gate != null) await gate.future;
    if (error != null) throw error;
  }

  @override
  Future<bool> addToQueue(
    List<SongEntity> nextSongs, {
    bool playNext = false,
  }) async {
    if (!nextAddResult) return false;
    songs = [...songs, ...nextSongs];
    return true;
  }

  @override
  Future<void> removeQueueItems(List<String> ids) async {
    final removed = ids.toSet();
    songs = songs.where((song) => !removed.contains(song.id)).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioPlayerState', () {
    test('copyWith can explicitly clear the current song', () {
      final song = _song('A');
      final state = AudioPlayerState(currentSong: song);

      expect(state.copyWith().currentSong, song);
      expect(state.copyWith(clearCurrentSong: true).currentSong, isNull);
    });
  });

  group('adjustIndexAfterMove', () {
    test('moving the playing entry carries the index with it', () {
      expect(AudioPlayerHandler.adjustIndexAfterMove(1, 1, 3), 3);
      expect(AudioPlayerHandler.adjustIndexAfterMove(3, 3, 0), 0);
    });

    test('moving an entry across the playing one shifts it by one', () {
      // [A,B,C,D,E], playing C(2); move A(0) after D(newIndex 3).
      expect(AudioPlayerHandler.adjustIndexAfterMove(2, 0, 3), 1);
      // Playing B(1); move D(3) to front.
      expect(AudioPlayerHandler.adjustIndexAfterMove(1, 3, 0), 2);
    });

    test('moves that do not cross the playing entry leave it alone', () {
      expect(AudioPlayerHandler.adjustIndexAfterMove(0, 2, 3), 0);
      expect(AudioPlayerHandler.adjustIndexAfterMove(4, 0, 1), 4);
      expect(AudioPlayerHandler.adjustIndexAfterMove(2, 0, 1), 2);
    });

    test('moving first to last and last to first', () {
      expect(AudioPlayerHandler.adjustIndexAfterMove(0, 0, 4), 4);
      expect(AudioPlayerHandler.adjustIndexAfterMove(4, 4, 0), 0);
      // Bystanders shift towards the gap.
      expect(AudioPlayerHandler.adjustIndexAfterMove(2, 0, 4), 1);
      expect(AudioPlayerHandler.adjustIndexAfterMove(2, 4, 0), 3);
    });

    test('agrees with a reference list move for every permutation', () {
      const length = 5;
      for (var oldIndex = 0; oldIndex < length; oldIndex++) {
        for (var newIndex = 0; newIndex < length; newIndex++) {
          for (var current = 0; current < length; current++) {
            final order = List<int>.generate(length, (i) => i);
            final movedId = order.removeAt(oldIndex);
            order.insert(newIndex, movedId);
            // The playing entry is identified by value, not position.
            final expected = order.indexOf(current);
            expect(
              AudioPlayerHandler.adjustIndexAfterMove(
                current,
                oldIndex,
                newIndex,
              ),
              expected,
              reason: 'current=$current old=$oldIndex new=$newIndex',
            );
          }
        }
      }
    });
  });

  group('AudioPlayerNotifier.reorderQueue (no handler)', () {
    late AudioPlayerNotifier notifier;

    setUp(() {
      notifier = AudioPlayerNotifier();
      notifier.state = AudioPlayerState(
        queue: [_song('A'), _song('B'), _song('C'), _song('D')],
        currentSong: _song('A'),
      );
    });

    tearDown(() {
      if (notifier.mounted) notifier.dispose();
    });

    test('move down lands exactly where dropped (onReorderItem semantics)', () {
      notifier.reorderQueue(0, 2);
      expect(_ids(notifier.state.queue), ['B', 'C', 'A', 'D']);
    });

    test('move up lands exactly where dropped', () {
      notifier.reorderQueue(3, 0);
      expect(_ids(notifier.state.queue), ['D', 'A', 'B', 'C']);
    });

    test('move to end of queue', () {
      notifier.reorderQueue(0, 3);
      expect(_ids(notifier.state.queue), ['B', 'C', 'D', 'A']);
    });

    test('same index and out-of-range indices are no-ops', () {
      notifier.reorderQueue(1, 1);
      expect(_ids(notifier.state.queue), ['A', 'B', 'C', 'D']);
      notifier.reorderQueue(-1, 2);
      notifier.reorderQueue(0, 4);
      notifier.reorderQueue(9, 0);
      expect(_ids(notifier.state.queue), ['A', 'B', 'C', 'D']);
    });

    test('successive drags apply to the already-updated order', () {
      // Regression test for the reorder glitch: the second drag must see
      // the result of the first immediately, not after an async round-trip.
      notifier.state = AudioPlayerState(
        queue: [_song('A'), _song('B'), _song('C'), _song('D'), _song('E')],
      );
      notifier.reorderQueue(0, 2); // [B,C,A,D,E]
      expect(_ids(notifier.state.queue), ['B', 'C', 'A', 'D', 'E']);
      notifier.reorderQueue(0, 4); // move B to the end -> [C,A,D,E,B]
      expect(_ids(notifier.state.queue), ['C', 'A', 'D', 'E', 'B']);
    });

    test(
      'deleting a pending current song keeps the next pending request',
      () async {
        final a = _song('A');
        final b = _song('B');
        await notifier.playSong(a, [a, b]);

        await notifier.handleSongsRemoved(['A']);

        expect(notifier.state.currentSong?.id, 'B');
        expect(_ids(notifier.state.queue), ['B']);
        expect(notifier.state.isPlaying, isFalse);
      },
    );

    test('deleting the only pending song clears all playback state', () async {
      final a = _song('A');
      await notifier.playSong(a, [a]);

      await notifier.handleSongsRemoved(['A']);

      expect(notifier.state.currentSong, isNull);
      expect(notifier.state.queue, isEmpty);
      expect(notifier.state.position, Duration.zero);
      expect(notifier.state.totalDuration, Duration.zero);
    });

    test('deleting a non-current pending song filters its queue', () async {
      final a = _song('A');
      final b = _song('B');
      final c = _song('C');
      await notifier.playSong(a, [a, b, c]);

      await notifier.handleSongsRemoved(['B']);

      expect(notifier.state.currentSong?.id, 'A');
      expect(_ids(notifier.state.queue), ['A', 'C']);
    });

    test('queue insertion is distinct from an unavailable player', () async {
      final song = _song('A');
      expect(await notifier.addToQueue(song), QueueAddResult.playerUnavailable);
    });

    test(
      'committed metadata updates playback pending before handler attach',
      () async {
        final song = _song('A');
        final handler = _FakeAudioPlayerHandler();
        addTearDown(handler.dispose);
        await notifier.playSong(song, [song]);
        notifier.applyCommittedSong(song.copyWith(isFavorite: true));

        notifier.setHandler(handler);
        await Future<void>.delayed(Duration.zero);

        expect(handler.songs.single.isFavorite, isTrue);
      },
    );

    test(
      'late handler attachment receives only the filtered pending request',
      () async {
        final a = _song('A');
        final b = _song('B');
        final handler = _FakeAudioPlayerHandler();
        addTearDown(handler.dispose);
        await notifier.playSong(a, [a, b]);
        await notifier.handleSongsRemoved(['A']);

        notifier.setHandler(handler);
        await Future<void>.delayed(Duration.zero);

        expect(_ids(handler.songs), ['B']);
        expect(handler.wantsPlayback, isTrue);
      },
    );
  });

  group('AudioPlayerNotifier song removal with a handler', () {
    late AudioPlayerNotifier notifier;
    late _FakeAudioPlayerHandler handler;

    setUp(() {
      notifier = AudioPlayerNotifier();
      handler = _FakeAudioPlayerHandler();
    });

    tearDown(() {
      if (notifier.mounted) notifier.dispose();
      handler.dispose();
    });

    test('a stale play failure cannot pause a newer song', () async {
      final a = _song('A');
      final b = _song('B');
      final gate = Completer<void>();
      handler.nextSetQueueGate = gate;
      handler.nextSetQueueError = StateError('old source failed');
      notifier.setHandler(handler);

      final oldRequest = notifier.playSong(a, [a]);
      final newRequest = notifier.playSong(b, [b]);
      await newRequest;
      gate.complete();
      await oldRequest;

      expect(notifier.state.currentSong?.id, 'B');
      expect(notifier.state.isPlaying, isTrue);
    });

    test(
      'a completion after notifier disposal does not publish state',
      () async {
        final song = _song('A');
        final gate = Completer<void>();
        handler.nextSetQueueGate = gate;
        notifier.setHandler(handler);

        final request = notifier.playSong(song, [song]);
        notifier.dispose();
        gate.complete();
        await expectLater(request, completes);
      },
    );

    test('committed favorite metadata preserves duplicate entry identity', () {
      final song = _song('A');
      final duplicate = song.copyWith(title: 'Duplicate');
      handler.songs = [song, duplicate];
      notifier
        ..state = AudioPlayerState(currentSong: song, queue: [song, duplicate])
        ..setHandler(handler);

      final committed = song.copyWith(isFavorite: true);
      notifier.applyCommittedSong(committed);

      expect(notifier.state.currentSong?.isFavorite, isTrue);
      expect(notifier.state.queue.every((song) => song.isFavorite), isTrue);
      expect(notifier.state.queue[0], isNot(same(notifier.state.queue[1])));
      expect(handler.songs.every((song) => song.isFavorite), isTrue);
      expect(handler.songs[0], isNot(same(handler.songs[1])));
    });

    test('queue insertion reports added and duplicate outcomes', () async {
      notifier.setHandler(handler);
      final song = _song('A');

      handler.nextAddResult = true;
      expect(await notifier.addToQueue(song), QueueAddResult.added);
      handler.nextAddResult = false;
      expect(await notifier.addToQueue(song), QueueAddResult.alreadyQueued);
    });

    test('replacing a stopped current song never requests playback', () async {
      final a = _song('A');
      final b = _song('B');
      handler.songs = [a, b];
      handler.wantsPlayback = false;
      notifier
        ..state = AudioPlayerState(
          currentSong: a,
          queue: [a, b],
          isPlaying: false,
        )
        ..setHandler(handler);

      await notifier.handleSongsRemoved(['A']);

      expect(handler.lastPlayWhenReady, isFalse);
      expect(_ids(handler.songs), ['B']);
      expect(notifier.state.currentSong?.id, 'B');
      expect(notifier.state.isPlaying, isFalse);
    });

    test(
      'deleting the only current song explicitly clears now playing',
      () async {
        final a = _song('A');
        handler.songs = [a];
        handler.wantsPlayback = false;
        notifier
          ..state = AudioPlayerState(currentSong: a, queue: [a])
          ..setHandler(handler);

        await notifier.handleSongsRemoved(['A']);

        expect(handler.songs, isEmpty);
        expect(notifier.state.currentSong, isNull);
        expect(notifier.state.queue, isEmpty);
        expect(notifier.state.isPlaying, isFalse);
      },
    );
  });

  test('stopped queue removal replaces the retained native source', () async {
    final handler = AudioPlayerHandler(initialSettings: const AppSettings());
    addTearDown(handler.dispose);
    final a = _song('A');
    final b = _song('B');

    await handler.setQueue([a, b], initialSong: a, playWhenReady: false);
    await handler.stop();
    await handler.removeQueueItems(['B']);

    expect(handler.sourceSongIds, ['A']);
    expect(handler.currentSong?.id, 'A');
    expect(handler.wantsPlayback, isFalse);
  });

  group('QueueScreen', () {
    testWidgets('queue with duplicate songs renders without key collisions', (
      tester,
    ) async {
      final notifier = AudioPlayerNotifier();
      final first = _song('same-id', 'Same Song');
      final second = _song('same-id', 'Same Song');
      notifier.state = AudioPlayerState(
        queue: [first, _song('other', 'Other Song'), second],
        currentSong: first,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerStateProvider.overrideWith((ref) => notifier),
            nowPlayingThemeSpecProvider.overrideWithValue(
              nowPlayingThemeSpecs[NowPlayingTheme.classic]!,
            ),
          ],
          child: const MaterialApp(home: QueueScreen()),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Both copies of the duplicated song are visible as separate rows.
      expect(find.text('Same Song'), findsNWidgets(2));
      expect(find.text('Other Song'), findsOneWidget);
    });
  });
}
