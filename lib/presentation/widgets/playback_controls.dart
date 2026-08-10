import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';

class PlaybackControls extends ConsumerWidget {
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const PlaybackControls({
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.skip_previous, color: theme.colorScheme.onSurface),
          onPressed: onPrevious ?? () => ref.read(audioPlayerProvider.notifier).skipToPrevious(),
        ),
        _buildPlayPauseButton(theme, ref),
        IconButton(
          icon: Icon(Icons.skip_next, color: theme.colorScheme.onSurface),
          onPressed: onNext ?? () => ref.read(audioPlayerProvider.notifier).skipToNext(),
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton(ThemeData theme, WidgetRef ref) {
    final playerState = ref.watch(audioPlayerProvider);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          playerState.isPlaying ? Icons.pause : Icons.play_arrow,
          color: theme.colorScheme.onPrimary,
          size: 28,
        ),
        onPressed: onPlayPause ?? () => ref.read(audioPlayerProvider.notifier).togglePlayPause(),
      ),
    );
  }
}

class VolumeControl extends ConsumerWidget {
  final double initialVolume;

  const VolumeControl({this.initialVolume = 1.0, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(audioPlayerProvider).volume;

    return Row(
      children: [
        const Icon(Icons.volume_down, size: 18),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: (value) {
              ref.read(audioPlayerProvider.notifier).setVolume(value);
            },
            min: 0.0,
            max: 1.0,
            divisions: 100,
          ),
        ),
        const Icon(Icons.volume_up, size: 18),
      ],
    );
  }
}

class SeekBar extends ConsumerWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onChanged;

  const SeekBar({
    required this.position,
    required this.duration,
    this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationValue = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final positionValue = position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            thumbColor: Theme.of(context).colorScheme.primary,
          ),
          child: Slider(
            value: positionValue,
            max: durationValue,
            onChanged: (value) {
              onChanged?.call(Duration(milliseconds: value.toInt()));
              ref.read(audioPlayerProvider.notifier).seek(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position)),
              Text(_formatDuration(duration)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
