import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/presentation/providers/sleep_timer_provider.dart';

class _ControllableAudioNotifier extends AudioPlayerNotifier {
  int pauseCalls = 0;
  Completer<bool>? nextPause;

  @override
  Future<bool> pause() {
    pauseCalls++;
    return nextPause?.future ?? Future<bool>.value(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sleep timer clears only after pause succeeds', (tester) async {
    final audio = _ControllableAudioNotifier();
    final pauseGate = Completer<bool>();
    audio.nextPause = pauseGate;
    final container = ProviderContainer(
      overrides: [audioPlayerStateProvider.overrideWith((ref) => audio)],
    );
    addTearDown(container.dispose);

    final timer = container.read(sleepTimerProvider.notifier)
      ..startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(audio.pauseCalls, 1);
    expect(timer.state.isActive, isTrue);
    expect(timer.state.remaining, Duration.zero);
    expect(timer.state.selectedDuration, const Duration(seconds: 1));

    pauseGate.complete(true);
    await tester.pump();

    expect(timer.state.isActive, isFalse);
    expect(timer.state.selectedDuration, isNull);
  });

  testWidgets('failed pause keeps the sleep timer active at zero', (
    tester,
  ) async {
    final audio = _ControllableAudioNotifier();
    final pauseGate = Completer<bool>();
    audio.nextPause = pauseGate;
    final container = ProviderContainer(
      overrides: [audioPlayerStateProvider.overrideWith((ref) => audio)],
    );
    addTearDown(container.dispose);

    final timer = container.read(sleepTimerProvider.notifier)
      ..startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    pauseGate.complete(false);
    await tester.pump();

    expect(timer.state.isActive, isTrue);
    expect(timer.state.remaining, Duration.zero);
    expect(timer.state.selectedDuration, const Duration(seconds: 1));
  });

  testWidgets('restarting while pause is pending discards stale completion', (
    tester,
  ) async {
    final audio = _ControllableAudioNotifier();
    final pauseGate = Completer<bool>();
    audio.nextPause = pauseGate;
    final container = ProviderContainer(
      overrides: [audioPlayerStateProvider.overrideWith((ref) => audio)],
    );
    addTearDown(container.dispose);

    final timer = container.read(sleepTimerProvider.notifier)
      ..startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    timer.startTimer(const Duration(seconds: 10));
    pauseGate.complete(true);
    await tester.pump();

    expect(timer.state.isActive, isTrue);
    expect(timer.state.remaining, const Duration(seconds: 10));
    expect(timer.state.selectedDuration, const Duration(seconds: 10));
    timer.cancelTimer();
  });

  testWidgets('cancelling while pause is pending discards its completion', (
    tester,
  ) async {
    final audio = _ControllableAudioNotifier();
    final pauseGate = Completer<bool>();
    audio.nextPause = pauseGate;
    final container = ProviderContainer(
      overrides: [audioPlayerStateProvider.overrideWith((ref) => audio)],
    );
    addTearDown(container.dispose);

    final timer = container.read(sleepTimerProvider.notifier)
      ..startTimer(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    timer.cancelTimer();
    pauseGate.complete(true);
    await tester.pump();

    expect(timer.state.isActive, isFalse);
  });
}
