import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier(ref);
});

class SleepTimerState {
  final bool isActive;
  final Duration remaining;
  final Duration? selectedDuration;

  const SleepTimerState({
    this.isActive = false,
    this.remaining = Duration.zero,
    this.selectedDuration,
  });

  SleepTimerState copyWith({
    bool? isActive,
    Duration? remaining,
    Duration? selectedDuration,
  }) {
    return SleepTimerState(
      isActive: isActive ?? this.isActive,
      remaining: remaining ?? this.remaining,
      selectedDuration: selectedDuration ?? this.selectedDuration,
    );
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final Ref ref;
  Timer? _timer;
  Timer? _countdownTimer;
  StreamSubscription<PositionDiscontinuity>? _discontinuitySub;
  StreamSubscription<ProcessingState>? _processingSub;
  bool _endOfTrack = false;

  SleepTimerNotifier(this.ref) : super(const SleepTimerState());

  void startTimer(Duration duration) {
    _clearEndOfTrack();
    cancelTimer();

    _timer = Timer(duration, () {
      if (!mounted) return;
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _timer = null;
      _pausePlayback();
      state = const SleepTimerState();
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        return;
      }
      if (state.remaining > Duration.zero) {
        state = state.copyWith(remaining: state.remaining - const Duration(seconds: 1));
      } else {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
    });

    state = SleepTimerState(
      isActive: true,
      remaining: duration,
      selectedDuration: duration,
    );
  }

  /// Returns true when the end-of-track timer is armed, false when the audio
  /// handler is not available yet (nothing to listen to).
  bool startEndOfTrackTimer() {
    cancelTimer();
    _endOfTrack = true;
    final attached = _attachEndOfTrackListeners();
    if (!attached) {
      _endOfTrack = false;
      return false;
    }
    state = const SleepTimerState(
      isActive: true,
      selectedDuration: null,
    );
    return true;
  }

  bool _attachEndOfTrackListeners() {
    final handler = ref.read(audioHandlerProvider);
    if (handler == null) return false;

    _discontinuitySub = handler.player.positionDiscontinuityStream.listen((discontinuity) {
      if (!_endOfTrack) return;
      if (discontinuity.reason != PositionDiscontinuityReason.autoAdvance) return;
      _finishEndOfTrack();
    });

    _processingSub = handler.player.processingStateStream.listen((processingState) {
      if (!_endOfTrack) return;
      if (processingState == ProcessingState.completed) {
        _finishEndOfTrack();
      }
    });
    return true;
  }

  void _finishEndOfTrack() {
    if (!mounted || !_endOfTrack) return;
    _endOfTrack = false;
    _discontinuitySub?.cancel();
    _processingSub?.cancel();
    _discontinuitySub = null;
    _processingSub = null;
    _pausePlayback();
    state = const SleepTimerState();
  }

  void _clearEndOfTrack() {
    _endOfTrack = false;
    _discontinuitySub?.cancel();
    _processingSub?.cancel();
    _discontinuitySub = null;
    _processingSub = null;
  }

  void cancelTimer() {
    _clearEndOfTrack();
    _timer?.cancel();
    _countdownTimer?.cancel();
    _timer = null;
    _countdownTimer = null;
    state = const SleepTimerState();
  }

  void _pausePlayback() {
    try {
      final playerNotifier = ref.read(audioPlayerProvider.notifier);
      playerNotifier.pause();
    } catch (_) {}
  }

  String get formattedRemaining {
    if (state.selectedDuration == null) {
      return 'End of current track';
    }
    final hours = state.remaining.inHours;
    final minutes = state.remaining.inMinutes % 60;
    final seconds = state.remaining.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  @override
  void dispose() {
    _clearEndOfTrack();
    _timer?.cancel();
    _timer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    super.dispose();
  }
}
