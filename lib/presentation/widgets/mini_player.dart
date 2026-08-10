import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:go_router/go_router.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  bool _showVolume = false;
  double _volume = 1.0;
  late AnimationController _bounceController;
  bool _showingBounce = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final song = playerState.currentSong;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (song == null) return const SizedBox.shrink();

    final progress = playerState.totalDuration.inMilliseconds > 0
        ? playerState.position.inMilliseconds / playerState.totalDuration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: _showVolume
          ? null
          : () async {
              await HapticFeedback.lightImpact();
              context.push('/now-playing');
            },
      onVerticalDragStart: _showVolume
          ? null
          : (details) {
              setState(() => _showVolume = true);
            },
      onVerticalDragEnd: _showVolume
          ? (details) {
              if ((details.primaryVelocity ?? 0) > 100) {
                setState(() => _showVolume = false);
              }
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _showVolume ? 100 : 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showVolume)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.volume_off, size: 16),
                    Expanded(
                      child: Slider(
                        value: _volume,
                        onChanged: (v) {
                          setState(() => _volume = v);
                          ref.read(audioPlayerProvider.notifier).setVolume(v);
                        },
                        activeColor: colorScheme.primary,
                      ),
                    ),
                    const Icon(Icons.volume_up, size: 16),
                  ],
                ),
              )
            else
              SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _buildAlbumArt(song, colorScheme),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: colorScheme.onSurface,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        ref.read(audioPlayerProvider.notifier).skipToPrevious();
                      },
                    ),
                    AnimatedBuilder(
                      animation: _bounceController,
                      builder: (context, child) {
                        final scale = _showingBounce
                            ? 1.0 + 0.1 * (1.0 - _bounceController.value) * _bounceController.value * 4
                            : 1.0;
                        return Transform.scale(
                          scale: scale,
                          child: child!,
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: colorScheme.onPrimary,
                            size: 24,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: () async {
                            await HapticFeedback.lightImpact();
                            ref.read(audioPlayerProvider.notifier).togglePlayPause();
                            if (!_showingBounce) {
                              _showingBounce = true;
                              _bounceController.forward(from: 0.0).then((_) {
                                _showingBounce = false;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: colorScheme.onSurface,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        ref.read(audioPlayerProvider.notifier).skipToNext();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumArt(SongEntity song, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: _hasArtwork(song)
            ? Image.file(
                File(song.coverArtPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(colorScheme),
              )
            : _placeholder(colorScheme),
      ),
    );
  }

  bool _hasArtwork(SongEntity song) {
    return song.coverArtPath != null &&
        song.coverArtPath!.isNotEmpty &&
        File(song.coverArtPath!).existsSync();
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onPrimaryContainer,
        size: 22,
      ),
    );
  }
}


