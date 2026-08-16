import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/domain/entities/playlist_entity.dart';

/// Trailing "⋮" (3-dot) menu for a song tile.
///
/// Used on the library and playlist detail screens so the song actions are
/// reachable without a long press. When [playlistId] is provided the menu
/// also offers playlist-scoped actions (move to another playlist, remove
/// from this playlist) instead of the library-scoped remove action.
class SongActionsMenu extends ConsumerWidget {
  final SongEntity song;
  final String? playlistId;

  const SongActionsMenu({super.key, required this.song, this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inPlaylist = playlistId != null;
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => _onSelected(context, ref, value),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'play_next',
          child: _MenuItem(icon: Icons.skip_next, label: 'Play Next'),
        ),
        const PopupMenuItem(
          value: 'add_queue',
          child: _MenuItem(icon: Icons.queue_music, label: 'Add to Queue'),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: _MenuItem(
            icon: song.isFavorite ? Icons.favorite : Icons.favorite_border,
            label: song.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            color: song.isFavorite ? Theme.of(ctx).colorScheme.error : null,
          ),
        ),
        const PopupMenuItem(
          value: 'add_playlist',
          child: _MenuItem(icon: Icons.playlist_add, label: 'Add to Playlist...'),
        ),
        if (inPlaylist)
          const PopupMenuItem(
            value: 'move_playlist',
            child: _MenuItem(icon: Icons.drive_file_move_outline, label: 'Move to Playlist...'),
          ),
        if (inPlaylist)
          PopupMenuItem(
            value: 'remove_playlist',
            child: _MenuItem(
              icon: Icons.remove_circle_outline,
              label: 'Remove from Playlist',
              color: Theme.of(ctx).colorScheme.error,
            ),
          ),
        if (!inPlaylist)
          PopupMenuItem(
            value: 'remove_library',
            child: _MenuItem(
              icon: Icons.delete_outline,
              label: 'Remove from Library',
              color: Theme.of(ctx).colorScheme.error,
            ),
          ),
        const PopupMenuItem(
          value: 'info',
          child: _MenuItem(icon: Icons.info_outline, label: 'Song Info'),
        ),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, WidgetRef ref, String value) async {
    await HapticFeedback.lightImpact();
    if (!context.mounted) return;
    switch (value) {
      case 'play_next':
        await ref.read(audioPlayerProvider.notifier).addToQueue(song, playNext: true);
        if (context.mounted) _showSnack(context, 'Added next in queue');
        break;
      case 'add_queue':
        await ref.read(audioPlayerProvider.notifier).addToQueue(song);
        if (context.mounted) _showSnack(context, 'Added to queue');
        break;
      case 'favorite':
        ref.read(libraryProvider.notifier).toggleFavorite(song.id);
        break;
      case 'add_playlist':
        await _pickPlaylist(context, ref, move: false);
        break;
      case 'move_playlist':
        await _pickPlaylist(context, ref, move: true);
        break;
      case 'remove_playlist':
        await _confirmRemoveFromPlaylist(context, ref);
        break;
      case 'remove_library':
        await _confirmRemoveFromLibrary(context, ref);
        break;
      case 'info':
        _showSongInfo(context);
        break;
    }
  }

  Future<void> _pickPlaylist(BuildContext context, WidgetRef ref, {required bool move}) async {
    final playlists = ref
        .read(playlistProvider)
        .playlists
        .where((p) => p.id != playlistId)
        .toList();
    if (playlists.isEmpty) {
      _showSnack(context, 'No other playlists yet');
      return;
    }

    final target = await showModalBottomSheet<PlaylistEntity>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                move ? 'Move to Playlist' : 'Add to Playlist',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...playlists.map((p) => ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, p),
            )),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;

    final notifier = ref.read(playlistProvider.notifier);
    await notifier.addSongToPlaylist(target.id, song.id);
    if (move && playlistId != null) {
      await notifier.removeSongFromPlaylist(playlistId!, song.id);
    }
    if (context.mounted) {
      _showSnack(context, move ? 'Moved to ${target.name}' : 'Added to ${target.name}');
    }
  }

  Future<void> _confirmRemoveFromPlaylist(BuildContext context, WidgetRef ref) async {
    if (playlistId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove song?'),
        content: Text('Remove "${song.title}" from this playlist?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(playlistProvider.notifier).removeSongFromPlaylist(playlistId!, song.id);
    }
  }

  Future<void> _confirmRemoveFromLibrary(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Song'),
        content: Text('Remove "${song.title}" from your library?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(libraryProvider.notifier).removeSong(song.id);
    }
  }

  void _showSongInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuItem({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: effectiveColor),
        const SizedBox(width: 12),
        Text(label, style: color != null ? TextStyle(color: color) : null),
      ],
    );
  }
}