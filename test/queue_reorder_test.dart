import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/presentation/screens/now_playing/queue_screen.dart';
import 'package:celsius/presentation/themes/now_playing_theme_spec.dart';
import 'package:celsius/services/background_audio_service.dart';

SongEntity _song(String id, [String? title]) => SongEntity(
      id: id,
      title: title ?? 'Title $id',
      filePath: '/music/$id.mp3',
    );

List<String> _ids(List<SongEntity> songs) => [for (final s in songs) s.id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    tearDown(() => notifier.dispose());

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
        queue: [
          _song('A'),
          _song('B'),
          _song('C'),
          _song('D'),
          _song('E'),
        ],
      );
      notifier.reorderQueue(0, 2); // [B,C,A,D,E]
      expect(_ids(notifier.state.queue), ['B', 'C', 'A', 'D', 'E']);
      notifier.reorderQueue(0, 4); // move B to the end -> [C,A,D,E,B]
      expect(_ids(notifier.state.queue), ['C', 'A', 'D', 'E', 'B']);
    });
  });

  group('QueueScreen', () {
    testWidgets('queue with duplicate songs renders without key collisions',
        (tester) async {
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
