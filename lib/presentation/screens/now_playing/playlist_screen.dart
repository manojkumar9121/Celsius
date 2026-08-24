import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/presentation/themes/now_playing_theme_spec.dart';
import 'package:celsuis/presentation/themes/now_playing_theme_widgets.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(audioPlayerProvider).currentSong;

    return NowPlayingSubScreen(
      title: 'Playlist',
      body: song == null
          ? Center(
              child: Text(
                'No song playing',
                style: TextStyle(color: ref.watch(nowPlayingThemeSpecProvider).inkColor),
              ),
            )
          : _PlaylistList(song: song),
    );
  }
}

class _PlaylistList extends ConsumerWidget {
  final SongEntity song;
  const _PlaylistList({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textColor = ref.watch(nowPlayingThemeSpecProvider).inkColor;
    final playlists = ref.watch(playlistProvider).playlists;

    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_play, size: 64, color: textColor.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No playlists yet', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 16)),
            const SizedBox(height: 8),
            Text('Create a playlist first', style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final alreadyAdded = playlist.songIds.contains(song.id);
        return ListTile(
          leading: Icon(
            Icons.queue_music,
            color: alreadyAdded ? theme.colorScheme.primary : textColor.withValues(alpha: 0.7),
            size: 28,
          ),
          title: Text(
            playlist.name,
            style: TextStyle(
              color: alreadyAdded ? theme.colorScheme.primary : textColor,
              fontWeight: alreadyAdded ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${playlist.songIds.length} songs',
            style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13),
          ),
          trailing: alreadyAdded
              ? const Icon(Icons.check, color: Colors.green)
              : null,
          onTap: alreadyAdded
              ? null
              : () {
                  ref.read(playlistProvider.notifier).addSongToPlaylist(playlist.id, song.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added to ${playlist.name}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
        );
      },
    );
  }
}
