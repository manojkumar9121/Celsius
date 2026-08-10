import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(audioPlayerProvider).queue;
    final currentSong = ref.watch(audioPlayerProvider).currentSong;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: textColor),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('Queue (${queue.length} songs)', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _QueueList(queue: queue, currentSong: currentSong),
      ),
    );
  }
}

class _QueueList extends ConsumerWidget {
  final List<SongEntity> queue;
  final SongEntity? currentSong;

  const _QueueList({required this.queue, required this.currentSong});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music, size: 64, color: textColor.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Queue is empty', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 16)),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: queue.length,
      onReorder: (oldIndex, newIndex) {
        ref.read(audioPlayerProvider.notifier).reorderQueue(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final song = queue[index];
        final isCurrent = song.id == currentSong?.id;
        return ListTile(
          key: ValueKey(song.id),
          dense: true,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drag_handle, color: textColor.withValues(alpha: 0.3), size: 20),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: _QueueArt(song),
              ),
            ],
          ),
          title: Text(
            song.title,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? theme.colorScheme.primary : textColor,
              fontSize: 15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 13),
          ),
          trailing: isCurrent
              ? Icon(Icons.equalizer, color: theme.colorScheme.primary, size: 22)
              : null,
          onTap: () {
            ref.read(audioPlayerProvider.notifier).skipToQueueItem(index);
          },
        );
      },
    );
  }
}

class _QueueArt extends StatelessWidget {
  final SongEntity song;
  const _QueueArt(this.song);

  @override
  Widget build(BuildContext context) {
    final hasArt = song.coverArtPath != null &&
        song.coverArtPath!.isNotEmpty &&
        File(song.coverArtPath!).existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: hasArt
          ? Image.file(
              File(song.coverArtPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _Placeholder(),
            )
          : _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[800],
      child: const Icon(Icons.music_note, color: Colors.grey, size: 24),
    );
  }
}
