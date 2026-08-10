import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/domain/entities/playlist_entity.dart';
import 'package:go_router/go_router.dart';
import 'package:celsuis/core/widgets/cached_song_image.dart';
import 'package:celsuis/core/widgets/shimmer.dart';
import 'package:celsuis/core/widgets/create_playlist_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryProvider);
    final playlistState = ref.watch(playlistProvider);
    final songs = libraryState.songs;
    final isLoading = libraryState.isLoading;

    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 12) greeting = 'Good morning';
    else if (hour < 18) greeting = 'Good afternoon';
    else greeting = 'Good evening';

    final recentlyPlayed = songs
        .where((s) => s.lastPlayedAt != null && s.lastPlayedAt! > 0)
        .toList()
      ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
    final recentList = recentlyPlayed.take(5).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.read(libraryProvider.notifier).loadSongs();
                },
                child: isLoading
                    ? _buildLoadingState(context)
                    : SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          greeting,
                                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${songs.length} songs · ${playlistState.playlists.length} playlists',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (songs.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: () => context.push('/stats'),
                                      icon: const Icon(Icons.bar_chart, size: 18),
                                      label: const Text('Stats'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (recentList.isNotEmpty)
                              _buildSection(
                                context,
                                ref,
                                'Recently Played',
                                recentList,
                              ),
                            const SizedBox(height: 16),
                            _buildPlaylistSection(context, ref, playlistState.playlists, songs.isEmpty),
                            const SizedBox(height: 16),
                            if (songs.isNotEmpty)
                              _buildSection(
                                context,
                                ref,
                                'Newest Added',
                                (songs.toList()..sort((a, b) {
                                  final aDate = a.dateAdded ?? DateTime(0);
                                  final bDate = b.dateAdded ?? DateTime(0);
                                  return bDate.compareTo(aDate);
                                })).take(5).toList(),
                              ),
                            if (songs.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildFavoritesSection(context, ref, songs),
                            ],
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: ShimmerLine(height: 24, radius: 6),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: ShimmerLine(height: 16, radius: 4),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: ShimmerLine(height: 18, radius: 4),
            ),
            SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                itemBuilder: (ctx, index) => const ShimmerCard(),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: ShimmerLine(height: 18, radius: 4),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ShimmerCard(height: 120, width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, WidgetRef ref, String title, List<SongEntity> sectionSongs) {
    if (sectionSongs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sectionSongs.length,
            itemBuilder: (ctx, index) {
              final song = sectionSongs[index];
              return GestureDetector(
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  ref.read(audioPlayerStateProvider.notifier).playSong(song, sectionSongs);
                  context.push('/now-playing');
                },
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SongCoverImage(
                          coverArtPath: song.coverArtPath,
                          borderRadius: 10,
                          placeholderBuilder: (_, w, h) => _coverPlaceholder(song),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        song.title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song.artist,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesSection(BuildContext context, WidgetRef ref, List<SongEntity> songs) {
    final favorites = songs.where((s) => s.isFavorite).toList();
    if (favorites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          child: Row(
            children: [
              Icon(Icons.favorite, color: Theme.of(context).colorScheme.error, size: 20),
              SizedBox(width: 8),
              Text('Favorites', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: favorites.length,
            itemBuilder: (ctx, index) {
              final song = favorites[index];
              return GestureDetector(
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  ref.read(audioPlayerStateProvider.notifier).playSong(song, favorites);
                  context.push('/now-playing');
                },
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SongCoverImage(
                          coverArtPath: song.coverArtPath,
                          borderRadius: 10,
                          placeholderBuilder: (_, w, h) => _coverPlaceholder(song),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        song.title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song.artist,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder(SongEntity song) {
    final color = hashToColor(song.id);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.6)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.music_note, size: 36, color: Colors.white),
      ),
    );
  }

  Widget _buildPlaylistSection(BuildContext context, WidgetRef ref, List<PlaylistEntity> playlists, bool libraryEmpty) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Playlists', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                onPressed: () async {
                  await HapticFeedback.lightImpact();
                  await showCreatePlaylistDialog(context, ref);
                },
                tooltip: 'Create playlist',
              ),
            ],
          ),
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () async {
                await HapticFeedback.mediumImpact();
                await showCreatePlaylistDialog(context, ref);
              },
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.playlist_add, size: 36, color: colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        libraryEmpty
                            ? 'Add music then create a playlist'
                            : 'Create your first playlist',
                        style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 176,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final hasCover = playlist.coverArtPath != null &&
                    playlist.coverArtPath!.isNotEmpty &&
                    File(playlist.coverArtPath!).existsSync();
                return GestureDetector(
                  onTap: () => context.push('/playlist/${playlist.id}'),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: hasCover
                                ? Image.file(File(playlist.coverArtPath!), fit: BoxFit.cover)
                                : Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          colorScheme.primary,
                                          colorScheme.secondary,
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.queue_music, size: 32, color: Colors.white),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${playlist.songIds.length} songs',
                                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          playlist.name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
