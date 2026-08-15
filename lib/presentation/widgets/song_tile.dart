import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/core/widgets/cached_song_image.dart';

class SongTile extends ConsumerWidget {
  final SongEntity song;
  final bool isPlaying;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool dismissEnabled;

  const SongTile({
    required this.song,
    this.isPlaying = false,
    required this.onTap,
    this.trailing,
    this.dismissEnabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!dismissEnabled) {
      return _buildListTile(context, ref);
    }
    return Dismissible(
      key: Key(song.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        await HapticFeedback.mediumImpact();
        if (!context.mounted) return false;
        return await _showDeleteDialog(context);
      },
      onDismissed: (direction) {
        ref.read(libraryProvider.notifier).removeSong(song.id);
      },
      child: _buildListTile(context, ref),
    );
  }

  Widget _buildListTile(BuildContext context, WidgetRef ref) {
    final title = song.title;
    final artist = song.artist;
    final duration = song.durationMs > 0 ? _formatDuration(song.durationMs) : '';
    final colorScheme = Theme.of(context).colorScheme;
    final isPlaying = this.isPlaying;

    return ListTile(
      leading: SongCoverImage(
        coverArtPath: song.coverArtPath,
        placeholderBuilder: (_, w, h) => _defaultLeading(isPlaying, context),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: isPlaying ? colorScheme.primary : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$artist${duration.isNotEmpty ? ' · $duration' : ''}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ?? Text(
        duration.isNotEmpty ? duration : '',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      onTap: () async {
        await HapticFeedback.lightImpact();
        onTap();
      },
      onLongPress: () async {
        await HapticFeedback.mediumImpact();
        if (!context.mounted) return;
        _showSongOptions(context, ref, song);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _defaultLeading(bool isPlaying, BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isPlaying
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: isPlaying
            ? Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary, size: 20)
            : Icon(Icons.music_note, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), size: 20),
      ),
    );
  }

  Future<void> _showSongOptions(BuildContext context, WidgetRef ref, SongEntity song) async {
    final playlistState = ref.read(playlistProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(song.isFavorite ? Icons.favorite : Icons.favorite_border, color: song.isFavorite ? Theme.of(context).colorScheme.error : null),
              title: const Text('Toggle Favorite'),
              onTap: () {
                ref.read(libraryProvider.notifier).toggleFavorite(song.id);
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            ...playlistState.playlists.map((playlist) => ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(playlist.name),
              onTap: () {
                ref.read(playlistProvider.notifier).addSongToPlaylist(playlist.id, song.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added to ${playlist.name}'), duration: const Duration(seconds: 1)),
                  );
                }
              },
            )),
            if (playlistState.playlists.isEmpty)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('No playlists'),
                subtitle: const Text('Create a playlist first'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Song Info'),
              onTap: () {
                Navigator.pop(context);
                _showSongInfo(context, song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSongInfo(BuildContext context, SongEntity song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Song Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title: ${song.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Artist: ${song.artist}'),
            Text('Album: ${song.album}'),
            Text('Duration: ${_formatDuration(song.durationMs)}'),
            Text('File: ${song.filePath}'),
            Text('Added: ${song.dateAdded?.toString().split(' ').first ?? 'Unknown'}'),
            Text('Play count: ${song.playCount}'),
            Text('Favorite: ${song.isFavorite ? 'Yes' : 'No'}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Song'),
        content: const Text('Remove this song from the library?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
