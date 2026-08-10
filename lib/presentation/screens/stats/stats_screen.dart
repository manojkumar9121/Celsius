import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/presentation/widgets/song_tile.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final songs = library.songs;
    final currentSong = ref.watch(audioPlayerProvider).currentSong;

    final totalSongs = songs.length;
    final totalDurationMs = songs.fold<int>(0, (sum, s) => sum + s.durationMs);
    final totalDuration = _formatDuration(Duration(milliseconds: totalDurationMs));

    final favorites = songs.where((s) => s.isFavorite).length;

    final topPlayed = [...songs]..sort((a, b) => b.playCount.compareTo(a.playCount));
    final mostPlayed = topPlayed.where((s) => s.playCount > 0).take(10).toList();

    final recentlyPlayed = [...songs]
      ..sort((a, b) => (b.lastPlayedAt ?? 0).compareTo(a.lastPlayedAt ?? 0));
    final recent = recentlyPlayed.where((s) => s.lastPlayedAt != null && s.lastPlayedAt! > 0).take(10).toList();

    final artistSet = songs.map((s) => s.artist).toSet();
    final albumSet = songs.map((s) => s.album).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening Activity'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildOverviewCard(context, totalSongs, favorites, artistSet.length, albumSet.length, totalDuration),
          const SizedBox(height: 20),
          if (mostPlayed.isNotEmpty) ...[
            _sectionTitle('Most Played'),
            const SizedBox(height: 8),
            ...mostPlayed.asMap().entries.map((e) => _buildMostPlayedTile(context, ref, e.value, e.key + 1, currentSong)),
            const SizedBox(height: 20),
          ],
          if (recent.isNotEmpty) ...[
            _sectionTitle('Recently Played'),
            const SizedBox(height: 8),
            ...recent.map((song) => SongTile(
              song: song,
              isPlaying: currentSong?.id == song.id,
              onTap: () {
                ref.read(audioPlayerProvider.notifier).playSong(song, recent);
                context.push('/now-playing');
              },
            )),
            const SizedBox(height: 20),
          ],
          if (favorites > 0) ...[
            _sectionTitle('Favorites'),
            const SizedBox(height: 8),
            ...songs.where((s) => s.isFavorite).take(10).map((song) => SongTile(
              song: song,
              isPlaying: currentSong?.id == song.id,
              onTap: () {
                ref.read(audioPlayerProvider.notifier).playSong(song, songs.where((s) => s.isFavorite).toList());
                context.push('/now-playing');
              },
            )),
          ],
          if (mostPlayed.isEmpty && recent.isEmpty && favorites == 0)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(Icons.headphones, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text(
                    'No listening data yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[400], fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Play some songs to see your stats here',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context, int songs, int favorites, int artists, int albums, String duration) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Library',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statColumn(Icons.music_note, '$songs', 'Songs'),
                _statColumn(Icons.favorite, '$favorites', 'Favorites'),
                _statColumn(Icons.person, '$artists', 'Artists'),
                _statColumn(Icons.album, '$albums', 'Albums'),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      'Total: $duration',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
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

  Widget _statColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.green),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildMostPlayedTile(BuildContext context, WidgetRef ref, SongEntity song, int rank, SongEntity? currentSong) {
    final isPlaying = currentSong?.id == song.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(
            '$rank',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: rank <= 3 ? Colors.green : Colors.grey[500],
            ),
          ),
        ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        '${song.artist} • ${song.playCount} plays',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isPlaying
          ? Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        ref.read(audioPlayerProvider.notifier).playSong(song, ref.read(libraryProvider).songs);
        context.push('/now-playing');
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }
}
