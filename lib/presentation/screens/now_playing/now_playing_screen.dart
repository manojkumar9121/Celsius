import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/settings_provider.dart';
import 'package:celsuis/presentation/providers/sleep_timer_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/core/utils/color_utils.dart';
import 'package:celsuis/presentation/widgets/waveform_viewer.dart';
import 'package:celsuis/services/waveform_extractor_service.dart';
import 'package:celsuis/core/widgets/cached_song_image.dart';

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

    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No song playing')),
      );
    }

    final avgColor = _dominantColorFor(song, theme.colorScheme.primary);
    final accentColor = theme.colorScheme.primary;
    final textColor = Colors.white;
    _ensureWaveformLoaded(song);
    _preloadUpcomingWaveforms(playerState, song);

    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: textColor),
        ),
      ),
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackground(song, avgColor),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                    final maxH = constraints.maxHeight;
                    final artSize = (maxH * 0.35).clamp(180.0, 340.0);
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: maxH),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              _buildTopBar(context, textColor),
                              const SizedBox(height: 8),
                              _buildAlbumArt(song, artSize),
                              const SizedBox(height: 20),
                              _buildSongInfo(song, textColor),
                              const SizedBox(height: 12),
                              _buildActionBar(song, accentColor, textColor),
                              const SizedBox(height: 4),
                              _buildSeekBar(playerState, accentColor, textColor),
                              const SizedBox(height: 4),
                              _buildTransportControls(playerState, accentColor, textColor),
                              const SizedBox(height: 12),
                              _buildWaveform(song),
                              const SizedBox(height: 8),
                              _buildBottomNavigation(textColor),
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

  Widget _buildWaveform(SongEntity song) {
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

    if (customColor != null) {
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

  Widget _buildBackground(SongEntity song, Color avgColor) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (song.coverArtPath != null && File(song.coverArtPath!).existsSync())
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Image.file(
              File(song.coverArtPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: avgColor),
            ),
          )
        else
          Container(color: avgColor),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.5),
                Colors.black.withValues(alpha: 0.65),
                Colors.black.withValues(alpha: 0.85),
                Colors.black,
              ],
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: textColor, size: 28),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.queue_music, color: textColor.withValues(alpha: 0.7), size: 20),
                onPressed: () => context.push('/queue'),
              ),
              IconButton(
                icon: Icon(Icons.timer_outlined, color: textColor.withValues(alpha: 0.7), size: 20),
                onPressed: _showSleepTimerDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(SongEntity song, double artSize) {
    final hasArt = song.coverArtPath != null &&
        song.coverArtPath!.isNotEmpty &&
        File(song.coverArtPath!).existsSync();

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
          child: Container(
            key: ValueKey('${song.id}:${song.coverArtPath}'),
            width: artSize,
            height: artSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: hasArt
                  ? Image.file(
                      File(song.coverArtPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _artPlaceholder(artSize, song),
                    )
                  : _artPlaceholder(artSize, song),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(SongEntity song, Color textColor) {
    final subtextColor = textColor.withValues(alpha: 0.6);
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
                  style: TextStyle(
                    color: textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  style: TextStyle(color: subtextColor, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(SongEntity song, Color accentColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPillButton(
            icon: song.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: song.isFavorite ? accentColor : textColor.withValues(alpha: 0.7),
            label: 'Favorite',
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
            color: textColor.withValues(alpha: 0.7),
            label: 'Save',
            onTap: () async {
              await HapticFeedback.lightImpact();
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar(AudioPlayerState playerState, Color accentColor, Color textColor) {
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
          Container(
            height: 32,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: textColor,
                inactiveTrackColor: textColor.withValues(alpha: 0.15),
                thumbColor: textColor,
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
                Text(
                  _formatDuration(position),
                  style: TextStyle(color: textColor, fontSize: 12),
                ),
                Text(
                  _formatDuration(total),
                  style: TextStyle(color: textColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportControls(AudioPlayerState playerState, Color accentColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded, color: playerState.isShuffled ? accentColor : textColor.withValues(alpha: 0.6), size: 20),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              ref.read(audioPlayerProvider.notifier).setShuffle(!playerState.isShuffled);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.skip_previous_rounded, color: textColor, size: 30),
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
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: textColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 40,
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
            icon: Icon(Icons.skip_next_rounded, color: textColor, size: 30),
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
                  ? accentColor
                  : textColor.withValues(alpha: 0.6),
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

  Widget _buildBottomNavigation(Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Row(
        children: [
          Expanded(
            child: _NavigationButton(
              title: 'Lyrics',
              icon: Icons.lyrics,
              color: textColor,
              onTap: () => context.push('/lyrics'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NavigationButton(
              title: 'Full Queue',
              icon: Icons.queue_music,
              color: textColor,
              onTap: () => context.push('/queue'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NavigationButton(
              title: 'Playlist',
              icon: Icons.playlist_play,
              color: textColor,
              onTap: () => context.push('/playlist'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _artPlaceholder(double size, SongEntity song) {
    final color = hashToColor(song.id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.5)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.music_note, size: size * 0.3, color: Colors.white.withValues(alpha: 0.7)),
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
      default:
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
              const Text('Music will stop at the end of current song'),
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
          ref.read(sleepTimerProvider.notifier).startEndOfTrackTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sleep timer set for end of track'),
              duration: Duration(seconds: 2),
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
  final Color color;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
