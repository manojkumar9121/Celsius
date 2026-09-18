import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/presentation/providers/library_provider.dart';
import 'package:celsius/presentation/providers/settings_provider.dart';
import 'package:celsius/presentation/providers/sleep_timer_provider.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/core/utils/color_utils.dart';
import 'package:celsius/presentation/widgets/waveform_viewer.dart';
import 'package:celsius/presentation/themes/now_playing_theme_spec.dart';
import 'package:celsius/presentation/themes/now_playing_theme_widgets.dart';
import 'package:celsius/services/waveform_extractor_service.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with TickerProviderStateMixin {
  final Map<String, Color> _dominantColorCache = {};
  final List<String> _dominantColorOrder = [];
  final Map<String, List<double>> _waveCache = {};
  final List<String> _waveCacheOrder = [];
  final Set<String> _waveLoading = {};
  Color _avgColor = const Color(0xFF1a1a2e);
  String? _avgColorSongId;
  double? _seekDragValue;
  late AnimationController _playBounceController;
  bool _showingPlayBounce = false;
  int _activeNavTab = 0;

  @override
  void initState() {
    super.initState();
    _playBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _playBounceController.dispose();
    super.dispose();
  }

  void _triggerPlayBounce(bool wasPlaying) {
    if (_showingPlayBounce) return;
    _showingPlayBounce = true;
    _playBounceController.forward(from: 0.0).then((_) {
      _showingPlayBounce = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final song = playerState.currentSong;
    final theme = Theme.of(context);
    final spec = ref.watch(nowPlayingThemeSpecProvider);

    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No song playing')),
      );
    }

    final avgColor = _dominantColorFor(song, theme.colorScheme.primary);
    final accentColor = theme.colorScheme.primary;
    _ensureWaveformLoaded(song);
    _preloadUpcomingWaveforms(playerState, song);

    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: spec.iconColor),
        ),
      ),
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          backgroundColor: spec.backgroundColor ?? Colors.black,
          body: Stack(
              fit: StackFit.expand,
              children: [
                NowPlayingBackground(spec: spec, song: song, avgColor: avgColor),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                    final maxH = constraints.maxHeight;
                    final maxW = constraints.maxWidth;
                    // Dynamic sizing: art scales with viewport height but never
                    // overflows narrow screens; gaps scale proportionally so
                    // short and tall phones distribute space evenly.
                    final artSize = math.min(
                      (maxH * 0.32).clamp(180.0, 340.0),
                      math.max(140.0, maxW - 48.0),
                    );
                    final gapSmall = (maxH * 0.008).clamp(4.0, 10.0);
                    final gapMedium = (maxH * 0.018).clamp(8.0, 20.0);
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: maxH),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              _buildTopBar(context, spec),
                              SizedBox(height: gapSmall),
                              _buildAlbumArt(song, artSize, playerState),
                              SizedBox(height: gapMedium),
                              _buildSongInfo(song, spec, playerState.isPlaying),
                              SizedBox(height: gapSmall),
                              _buildActionBar(song, accentColor, spec),
                              SizedBox(height: gapSmall),
                              _buildSeekBar(playerState, accentColor, spec),
                              SizedBox(height: gapSmall),
                              _buildTransportControls(playerState, accentColor, spec),
                              SizedBox(height: gapSmall),
                              _buildWaveform(song, spec),
                              SizedBox(height: gapSmall),
                              // Pins the 3 pills (queue/playlist/lyrics) to the
                              // bottom on tall screens; collapses to zero when
                              // content overflows and the view scrolls.
                              const Spacer(),
                              _buildBottomNavigation(spec),
                            ],
                          ),
                        ),
                      ),
                    );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildWaveform(SongEntity song, NowPlayingThemeSpec spec) {
    final settings = ref.watch(settingsProvider);

    final hasArt = song.coverArtPath != null &&
        song.coverArtPath!.isNotEmpty &&
        File(song.coverArtPath!).existsSync();

    final customColor = settings.waveformColor != '#4ade80'
        ? parseHexColor(settings.waveformColor)
        : null;

    final bool rainbow;
    Color? activeColor;
    Color? inactiveColor;
    List<Color>? gradient;

    if (spec.waveformPalette != null) {
      // Themed skins use their fixed palette instead of artwork colors.
      rainbow = false;
      activeColor = spec.waveformActiveColor;
      inactiveColor = spec.waveformInactiveColor;
      gradient = null;
    } else if (customColor != null) {
      rainbow = false;
      activeColor = customColor;
      inactiveColor = customColor.withValues(alpha: 0.3);
      gradient = null;
    } else if (hasArt) {
      rainbow = false;
      final baseColor = _vividColor(_avgColor);
      activeColor = baseColor;
      inactiveColor = baseColor.withValues(alpha: 0.3);
      gradient = [
        Color.lerp(baseColor, Colors.white, 0.3)!,
        baseColor,
        Color.lerp(baseColor, Colors.black, 0.15)!,
      ];
    } else {
      rainbow = true;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: WaveformViewer(
          key: ValueKey(song.id),
          waveData: _waveCache[song.id],
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          gradientColors: gradient,
          rainbow: rainbow,
          height: 48,
          showTimestamps: false,
          barPalette: spec.waveformPalette,
          squareBars: spec.waveformSquareBars,
          stripeOn: spec.waveformStripes ? 3 : null,
          stripeOff: spec.waveformStripes ? 2 : null,
          barGap: spec.waveformBarGap,
        ),
      ),
    );
  }

  void _preloadUpcomingWaveforms(AudioPlayerState playerState, SongEntity song) {
    final index = playerState.queue.indexWhere((s) => s.id == song.id);
    if (index < 0) return;
    final upper = (index + 3).clamp(0, playerState.queue.length);
    for (int i = index + 1; i < upper; i++) {
      _ensureWaveformLoaded(playerState.queue[i]);
    }
  }

  Future<void> _ensureWaveformLoaded(SongEntity song) async {
    final id = song.id;
    if (_waveCache.containsKey(id) || _waveLoading.contains(id)) return;

    // Skip tiny clips (voice notes, rings, notifications) - not worth extracting.
    if (song.durationMs > 0 && song.durationMs < 15000) {
      return;
    }

    _waveLoading.add(id);

    final path = song.realPath ?? song.filePath;
    if (path.isEmpty || path.startsWith('content://')) {
      _waveLoading.remove(id);
      return;
    }

    try {
      final data = await WaveformExtractorService.instance.extractWaveform(path);
      if (!mounted) return;
      setState(() {
        _waveCache[id] = data;
        _waveCacheOrder.add(id);
        // LRU eviction: keep only the most recent 100 waveforms in memory.
        while (_waveCacheOrder.length > 100) {
          final oldest = _waveCacheOrder.removeAt(0);
          _waveCache.remove(oldest);
        }
      });
    } catch (e) {
      debugPrint('Waveform extraction error for $id: $e');
    } finally {
      _waveLoading.remove(id);
    }
  }

  Color _vividColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lightness = hsl.lightness.clamp(0.4, 0.85);
    return hsl.withLightness(lightness).toColor();
  }

  Widget _buildTopBar(BuildContext context, NowPlayingThemeSpec spec) {
    final iconColor = spec.iconColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: iconColor, size: 28),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
          if (spec.topLabel != null)
            Expanded(
              child: Text(
                spec.topLabel!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: spec.topLabelStyle,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.queue_music, color: iconColor.withValues(alpha: 0.7), size: 20),
                onPressed: () => context.push('/queue'),
              ),
              IconButton(
                icon: Icon(Icons.timer_outlined, color: iconColor.withValues(alpha: 0.7), size: 20),
                onPressed: _showSleepTimerDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(SongEntity song, double artSize, AudioPlayerState playerState) {
    final queueIndex = playerState.queue.indexWhere((s) => s.id == song.id);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity!.abs() < 100) return;
        if (details.primaryVelocity! > 0) {
          HapticFeedback.lightImpact();
          ref.read(audioPlayerProvider.notifier).skipToPrevious();
        } else {
          HapticFeedback.lightImpact();
          ref.read(audioPlayerProvider.notifier).skipToNext();
        }
      },
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: NowPlayingArtFrame(
            key: ValueKey('${song.id}:${song.coverArtPath}'),
            spec: ref.watch(nowPlayingThemeSpecProvider),
            song: song,
            size: artSize,
            queueIndex: queueIndex < 0 ? null : queueIndex,
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(SongEntity song, NowPlayingThemeSpec spec, bool isPlaying) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: spec.titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  style: spec.artistStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (spec.showPlayStatus) ...[
                  const SizedBox(height: 2),
                  LcdStatusLine(playing: isPlaying),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(SongEntity song, Color accentColor, NowPlayingThemeSpec spec) {
    final heartColor = spec.pillHeartColor ??
        (song.isFavorite ? accentColor : spec.pillTextColor);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPillButton(
            icon: song.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: heartColor,
            label: 'Favorite',
            spec: spec,
            onTap: () async {
              await HapticFeedback.lightImpact();
              final newFav = !song.isFavorite;
              ref.read(libraryProvider.notifier).toggleFavorite(song.id);
              ref.read(audioPlayerProvider.notifier).updateCurrentSongFavorite(newFav);
            },
          ),
          const SizedBox(width: 12),
          _buildPillButton(
            icon: Icons.playlist_add,
            color: spec.pillHeartColor == null
                ? spec.pillTextColor
                : spec.pillTextColor.withValues(alpha: 0.7),
            label: 'Save',
            spec: spec,
            onTap: () async {
              await HapticFeedback.lightImpact();
              if (!mounted) return;
              context.push('/playlist');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    required NowPlayingThemeSpec spec,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: spec.pillBackgroundColor,
          borderRadius: BorderRadius.circular(spec.pillRadius),
          border: Border.all(
            // Classic follows the icon color like the original design;
            // themed skins use their fixed ink border.
            color: (spec.pillHeartColor == null ? color : spec.pillBorderColor)
                .withValues(alpha: spec.pillBorderAlpha),
            width: spec.pillBorderWidth,
          ),
          boxShadow: spec.pillShadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: (spec.pillTextStyle ?? const TextStyle()).merge(
                TextStyle(
                  color: (spec.pillHeartColor == null ? color : spec.pillTextColor)
                      .withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar(AudioPlayerState playerState, Color accentColor, NowPlayingThemeSpec spec) {
    final total = playerState.totalDuration;
    final position = playerState.position;
    final preview = _seekDragValue;
    final progress = preview ??
        (total.inMilliseconds > 0
            ? position.inMilliseconds / total.inMilliseconds
            : 0.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: SliderTheme(
              data: spec.sliderTheme() ??
                  SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                    thumbColor: Colors.white,
                    overlayColor: Colors.transparent,
                  ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) => setState(() => _seekDragValue = value),
                onChangeEnd: (value) {
                  final pos = Duration(milliseconds: (value * total.inMilliseconds).round());
                  ref.read(audioPlayerProvider.notifier).seek(pos);
                  setState(() => _seekDragValue = null);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position), style: spec.timeStyle),
                Text(_formatDuration(total), style: spec.timeStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportControls(AudioPlayerState playerState, Color accentColor, NowPlayingThemeSpec spec) {
    final iconColor = spec.transportColor;
    final activeColor = spec.transportActiveColor ?? accentColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded, color: playerState.isShuffled ? activeColor : iconColor.withValues(alpha: 0.6), size: 20),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              ref.read(audioPlayerProvider.notifier).setShuffle(!playerState.isShuffled);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.skip_previous_rounded, color: iconColor, size: 30),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              ref.read(audioPlayerProvider.notifier).skipToPrevious();
            },
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _playBounceController,
            builder: (context, child) {
              final scale = _showingPlayBounce
                  ? 1.0 + 0.1 * (1.0 - _playBounceController.value) * _playBounceController.value * 4
                  : 1.0;
              return Transform.scale(
                scale: scale,
                child: child!,
              );
            },
            child: Container(
              width: spec.playSize,
              height: spec.playSize,
              decoration: BoxDecoration(
                color: spec.playBackgroundColor,
                shape: spec.playRadius == null ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: spec.playRadius == null
                    ? null
                    : BorderRadius.circular(spec.playRadius!),
                boxShadow: spec.playShadows,
              ),
              child: IconButton(
                icon: Icon(
                  playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: spec.playForegroundColor,
                  size: spec.playIconSize,
                ),
                onPressed: () async {
                  await HapticFeedback.lightImpact();
                  final wasPlaying = playerState.isPlaying;
                  ref.read(audioPlayerProvider.notifier).togglePlayPause();
                  _triggerPlayBounce(wasPlaying);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.skip_next_rounded, color: iconColor, size: 30),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              ref.read(audioPlayerProvider.notifier).skipToNext();
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _repeatIcon(playerState.repeatMode),
              color: playerState.repeatMode != AppSettingsRepeatMode.off
                  ? activeColor
                  : iconColor.withValues(alpha: 0.6),
              size: 20,
            ),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              _cycleRepeatMode();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation(NowPlayingThemeSpec spec) {
    if (spec.navStyle == NowPlayingNavStyle.lcdBar) {
      return _buildLcdBar(spec);
    }
    return Padding(
      // SafeArea already applies the device bottom inset (gesture bar vs
      // 3-button nav), so keep only a small fixed margin here. A large fixed
      // value looked fine on gesture-nav phones but left a visible gap on
      // phones with a taller system nav bar.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _NavigationButton(
              title: 'Lyrics',
              icon: Icons.lyrics,
              spec: spec,
              onTap: () => context.push('/lyrics'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NavigationButton(
              title: 'Full Queue',
              icon: Icons.queue_music,
              spec: spec,
              onTap: () => context.push('/queue'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NavigationButton(
              title: 'Playlist',
              icon: Icons.playlist_play,
              spec: spec,
              onTap: () => context.push('/playlist'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLcdBar(NowPlayingThemeSpec spec) {
    final color = spec.navTextColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: spec.navBorderColor, width: 1.5),
            bottom: BorderSide(color: spec.navBorderColor, width: 1.5),
          ),
        ),
        child: Row(
          children: [
            _LcdNavTab(label: 'LYRICS', index: 0, active: _activeNavTab == 0, color: color, onTap: () { setState(() => _activeNavTab = 0); context.push('/lyrics'); }),
            _LcdNavDot(color: spec.navBorderColor),
            _LcdNavTab(label: 'QUEUE', index: 1, active: _activeNavTab == 1, color: color, onTap: () { setState(() => _activeNavTab = 1); context.push('/queue'); }),
            _LcdNavDot(color: spec.navBorderColor),
            _LcdNavTab(label: 'LIST', index: 2, active: _activeNavTab == 2, color: color, onTap: () { setState(() => _activeNavTab = 2); context.push('/playlist'); }),
          ],
        ),
      ),
    );
  }

  void _cycleRepeatMode() {
    final modes = AppSettingsRepeatMode.values;
    final current = ref.read(audioPlayerProvider).repeatMode;
    final nextIndex = (current.index + 1) % modes.length;
    ref.read(audioPlayerProvider.notifier).setRepeatMode(modes[nextIndex]);
  }

  IconData _repeatIcon(AppSettingsRepeatMode? mode) {
    switch (mode) {
      case AppSettingsRepeatMode.one:
        return Icons.repeat_one;
      case AppSettingsRepeatMode.all:
        return Icons.repeat;
      case AppSettingsRepeatMode.off:
        return Icons.repeat;
      case null:
        return Icons.repeat;
    }
  }

  Color _dominantColorFor(SongEntity song, Color themePrimary) {
    if (_avgColorSongId != song.id) {
      _avgColorSongId = song.id;
      _avgColor = _dominantColorCache[song.id] ?? themePrimary;
      _computeDominantColor(song, themePrimary);
    }
    return _avgColor;
  }

  Future<void> _computeDominantColor(SongEntity song, Color themePrimary) async {
    if (song.coverArtPath == null || !File(song.coverArtPath!).existsSync()) {
      return;
    }
    try {
      final bytes = await File(song.coverArtPath!).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      codec.dispose();
      frame.image.dispose();
      if (data == null) return;

      final result = dominantColorFromRgba(data.buffer.asUint8List(), themePrimary);

      if (_dominantColorCache.containsKey(song.id)) {
        _dominantColorOrder.remove(song.id);
      }
      _dominantColorCache[song.id] = result;
      _dominantColorOrder.add(song.id);
      while (_dominantColorOrder.length > 50) {
        final oldest = _dominantColorOrder.removeAt(0);
        _dominantColorCache.remove(oldest);
      }

      if (mounted && _avgColorSongId == song.id) {
        setState(() => _avgColor = result);
      }
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSleepTimerDialog() {
    final sleepTimer = ref.read(sleepTimerProvider);

    if (sleepTimer.isActive) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sleep Timer Active'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ref.read(sleepTimerProvider.notifier).formattedRemaining,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                sleepTimer.selectedDuration == null
                    ? 'Music will stop at the end of current song'
                    : 'Music will stop when the timer ends',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(sleepTimerProvider.notifier).cancelTimer();
                Navigator.pop(ctx);
              },
              child: const Text('Cancel Timer'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sleep Timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sleepTimerOption(ctx, '15 minutes', const Duration(minutes: 15)),
            _sleepTimerOption(ctx, '30 minutes', const Duration(minutes: 30)),
            _sleepTimerOption(ctx, '45 minutes', const Duration(minutes: 45)),
            _sleepTimerOption(ctx, '1 hour', const Duration(hours: 1)),
            _sleepTimerOption(ctx, '2 hours', const Duration(hours: 2)),
            _sleepTimerOption(ctx, 'End of track', null),
          ],
        ),
      ),
    );
  }

  Widget _sleepTimerOption(BuildContext context, String label, Duration? duration) {
    return ListTile(
      title: Text(label),
      leading: Icon(
        duration == null ? Icons.music_note : Icons.timer,
        color: Theme.of(context).colorScheme.primary,
      ),
      onTap: () {
        Navigator.pop(context);
        if (duration != null) {
          ref.read(sleepTimerProvider.notifier).startTimer(duration);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sleep timer set for $label'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          final armed = ref.read(sleepTimerProvider.notifier).startEndOfTrackTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(armed
                  ? 'Sleep timer set for end of track'
                  : 'Player not ready — try again in a moment'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }
}

class _NavigationButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final NowPlayingThemeSpec spec;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.title,
    required this.icon,
    required this.spec,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = spec.navTextColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: spec.navBackgroundColor,
          borderRadius: BorderRadius.circular(spec.navRadius),
          border: spec.navBorderColor == Colors.transparent
              ? null
              : Border.all(color: spec.navBorderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: spec.navTextStyle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LcdNavTab extends StatelessWidget {
  final String label;
  final int index;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _LcdNavTab({
    required this.label,
    required this.index,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: active
              ? BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                )
              : null,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: 6.5,
              color: active ? color : color.withValues(alpha: 0.55),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _LcdNavDot extends StatelessWidget {
  final Color color;

  const _LcdNavDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
    );
  }
}
