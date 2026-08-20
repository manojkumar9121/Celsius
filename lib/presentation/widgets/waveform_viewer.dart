import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/presentation/providers/settings_provider.dart';
import 'package:celsuis/presentation/widgets/waveform_painter.dart';

class WaveformViewer extends ConsumerStatefulWidget {
  final List<double>? waveData;
  final Color? activeColor;
  final Color? inactiveColor;
  final List<Color>? gradientColors;
  final bool rainbow;
  final double height;
  final bool showTimestamps;

  /// Per-bar color cycle (themed skins).
  final List<Color>? barPalette;

  /// Square bar caps (themed skins).
  final bool squareBars;

  /// Vertical ink stripes inside bars (Pocket LCD).
  final double? stripeOn;
  final double? stripeOff;

  /// Overrides the default 2.0 bar gap (themed skins).
  final double? barGap;

  const WaveformViewer({
    this.waveData,
    this.activeColor,
    this.inactiveColor,
    this.gradientColors,
    this.rainbow = false,
    this.height = 56,
    this.showTimestamps = true,
    this.barPalette,
    this.squareBars = false,
    this.stripeOn,
    this.stripeOff,
    this.barGap,
    super.key,
  });

  @override
  ConsumerState<WaveformViewer> createState() => _WaveformViewerState();
}

class _WaveformViewerState extends ConsumerState<WaveformViewer>
    with TickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeColor = widget.activeColor ??
        (isDark ? Colors.greenAccent : const Color(0xFF1DB954));
    final inactiveColor = widget.inactiveColor ??
        (isDark ? Colors.white24 : Colors.black26);

    final drawStyle = switch (settings.waveformStyle) {
      WaveformStyle.bars => WaveformDrawStyle.bars,
      WaveformStyle.line => WaveformDrawStyle.line,
      WaveformStyle.ribbon => WaveformDrawStyle.ribbon,
      WaveformStyle.wave => WaveformDrawStyle.wave,
      WaveformStyle.dots => WaveformDrawStyle.dots,
      WaveformStyle.equalizer => WaveformDrawStyle.equalizer,
      WaveformStyle.blocks => WaveformDrawStyle.blocks,
      WaveformStyle.neon => WaveformDrawStyle.neon,
      WaveformStyle.radial => WaveformDrawStyle.radial,
    };

    final speed = settings.waveformAnimationSpeed;
    final targetDuration = Duration(
      milliseconds: (1000 / speed).round(),
    );
    if (_animation.duration != targetDuration) {
      _animation.duration = targetDuration;
    }
    if (playerState.isPlaying) {
      if (!_animation.isAnimating) {
        _animation.repeat();
      }
    } else if (_animation.isAnimating) {
      _animation.stop();
    }

    final total = playerState.totalDuration.inMilliseconds > 0
        ? playerState.totalDuration
        : Duration.zero;
    final progress = total.inMilliseconds > 0
        ? playerState.position.inMilliseconds / total.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: WaveformPainter(
              waveData: widget.waveData ?? _fallbackData,
              progress: progress.clamp(0.0, 1.0),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              gradientColors: widget.gradientColors,
              style: drawStyle,
              rainbow: widget.rainbow,
              barWidth: drawStyle == WaveformDrawStyle.radial ? 2.0 : 3.0,
              barSpacing: widget.barGap ??
                  (drawStyle == WaveformDrawStyle.radial ? 1.0 : 2.0),
              barPalette: widget.barPalette,
              squareBars: widget.squareBars,
              stripeOn: widget.stripeOn,
              stripeOff: widget.stripeOff,
              animation: playerState.isPlaying ? _animation : null,
            ),
          ),
        ),
        if (widget.showTimestamps)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(playerState.position),
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  _formatDuration(total),
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<double> get _fallbackData => List.generate(60, (i) {
    final x = i / 59;
    return (0.3 + 0.4 * (x < 0.5 ? x * 2 : (1 - x) * 2)).clamp(0.1, 1.0);
  });

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}