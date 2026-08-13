import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/presentation/widgets/song_tile.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/core/widgets/cached_song_image.dart';
import 'package:go_router/go_router.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> with SingleTickerProviderStateMixin {
  late AnimationController _coverController;

  @override
  void initState() {
    super.initState();
    _coverController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _coverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistState = ref.watch(playlistProvider);
    final playlist = playlistState.playlists.where((pl) => pl.id == widget.playlistId).firstOrNull;
    final libraryState = ref.watch(libraryProvider);
    final allSongs = libraryState.songs;
    final currentSong = ref.watch(audioPlayerProvider).currentSong;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (playlist == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return Scaffold(
        appBar: AppBar(title: const Text('Playlist')),
        body: Center(child: Text('Playlist not found', style: textTheme.bodyLarge)),
      );
    }

    final playlistSongs = playlist.songIds
        .map((id) => allSongs.where((s) => s.id == id).firstOrNull)
        .whereType<SongEntity>()
        .toList();

    final hasCover = playlist.coverArtPath != null && playlist.coverArtPath!.isNotEmpty && File(playlist.coverArtPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        centerTitle: true,
        actions: [
          if (playlistSongs.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) async {
                await HapticFeedback.lightImpact();
                if (value == 'play_all') {
                  ref.read(audioPlayerProvider.notifier).playSong(playlistSongs.first, playlistSongs);
                  if (context.mounted) context.push('/now-playing');
                } else if (value == 'shuffle') {
                  final shuffled = [...playlistSongs]..shuffle();
                  ref.read(audioPlayerProvider.notifier).playSong(shuffled.first, shuffled);
                  if (context.mounted) context.push('/now-playing');
                } else if (value == 'rename') {
                  _showRenameDialog(playlist);
                } else if (value == 'change_cover') {
                  await _pickPlaylistCover(playlist.id);
                } else if (value == 'delete') {
                  await HapticFeedback.mediumImpact();
                  ref.read(playlistProvider.notifier).deletePlaylist(playlist.id);
                  if (context.mounted) context.go('/library');
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'play_all', child: Text('Play All')),
                const PopupMenuItem(value: 'shuffle', child: Text('Shuffle')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'change_cover', child: Text('Change Cover')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: colorScheme.error)),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    _coverController.forward();
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) _coverController.reverse();
                    });
                  },
                  child: AnimatedBuilder(
                    animation: _coverController,
                    builder: (context, child) {
                      final scale = 1.0 + (_coverController.value * 0.05);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
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
                                    child: Icon(Icons.queue_music, color: colorScheme.onPrimary, size: 56),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  playlist.name,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlistSongs.length} ${playlistSongs.length == 1 ? 'song' : 'songs'}',
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: playlistSongs.isEmpty
                          ? null
                          : () async {
                              await HapticFeedback.lightImpact();
                              ref.read(audioPlayerProvider.notifier).playSong(playlistSongs.first, playlistSongs);
                              if (context.mounted) context.push('/now-playing');
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: playlistSongs.isEmpty
                          ? null
                          : () async {
                              await HapticFeedback.lightImpact();
                              final shuffled = [...playlistSongs]..shuffle();
                              ref.read(audioPlayerProvider.notifier).playSong(shuffled.first, shuffled);
                              if (context.mounted) context.push('/now-playing');
                            },
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: playlistSongs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue_music, size: 64, color: colorScheme.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          'No songs yet',
                          style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + to add songs from your library',
                          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.4)),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: playlistSongs.length,
                    onReorder: (oldIndex, newIndex) async {
                      await HapticFeedback.lightImpact();
                      if (newIndex > oldIndex) newIndex--;
                      final songIds = List<String>.from(playlist.songIds);
                      final item = songIds.removeAt(oldIndex);
                      songIds.insert(newIndex, item);
                      ref.read(playlistProvider.notifier).updatePlaylist(playlist.id, songIds: songIds);
                    },
                    itemBuilder: (context, index) {
                      final song = playlistSongs[index];
                      final isPlaying = currentSong?.id == song.id;
                      return SongTile(
                        key: ValueKey(song.id),
                        song: song,
                        isPlaying: isPlaying,
                        dismissEnabled: false,
                        trailing: IconButton(
                          icon: Icon(Icons.remove_circle_outline, color: colorScheme.error),
                          tooltip: 'Remove from playlist',
                          onPressed: () async {
                            await HapticFeedback.mediumImpact();
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Remove song?'),
                                content: Text('Remove "${song.title}" from this playlist?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              ref.read(playlistProvider.notifier).removeSongFromPlaylist(playlist.id, song.id);
                            }
                          },
                        ),
                        onTap: () async {
                          await HapticFeedback.lightImpact();
                          ref.read(audioPlayerProvider.notifier).playSong(song, playlistSongs);
                          if (context.mounted) context.push('/now-playing');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await HapticFeedback.lightImpact();
          _showAddSongsSheet(playlist.id, playlistSongs);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddSongsSheet(String playlistId, List<SongEntity> currentSongs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddSongsSheet(
        playlistId: playlistId,
        initialSongs: currentSongs,
      ),
    );
  }

  void _showRenameDialog(dynamic playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(playlistProvider.notifier).renamePlaylist(playlist.id, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPlaylistCover(String playlistId) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.first.path!);
    final appDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${appDir.path}/playlist_covers');
    if (!await coversDir.exists()) await coversDir.create(recursive: true);

    final ext = p.extension(result.files.first.name);
    final destPath = '${coversDir.path}/$playlistId$ext';
    await file.copy(destPath);

    ref.read(playlistProvider.notifier).updatePlaylistCover(playlistId, destPath);
  }
}

class _AddSongsSheet extends ConsumerStatefulWidget {
  final String playlistId;
  final List<SongEntity> initialSongs;

  const _AddSongsSheet({
    required this.playlistId,
    required this.initialSongs,
  });

  @override
  ConsumerState<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<_AddSongsSheet> {
  late List<SongEntity> _selectedSongs;

  @override
  void initState() {
    super.initState();
    _selectedSongs = List.from(widget.initialSongs);
  }

  @override
  Widget build(BuildContext context) {
    final allSongs = ref.watch(libraryProvider).songs;
    final currentIds = _selectedSongs.map((s) => s.id).toSet();
    final available = allSongs.where((s) => !currentIds.contains(s.id)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add Songs (${_selectedSongs.length} in playlist)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (available.isEmpty)
            const Expanded(
              child: Center(
                child: Text('All songs are already in this playlist'),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: available.length,
                itemBuilder: (ctx, index) {
                  final song = available[index];
                  return ListTile(
                    leading: SongCoverImage(
                      coverArtPath: song.coverArtPath,
                      width: 40,
                      height: 40,
                      borderRadius: 6,
                      placeholderBuilder: (_, w, h) => _placeholder(context, w, h),
                    ),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        ref.read(playlistProvider.notifier).addSongToPlaylist(widget.playlistId, song.id);
                        setState(() {
                          _selectedSongs = [..._selectedSongs, song];
                        });
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, double w, double h) {
    return Container(
      width: w,
      height: h,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note, color: Colors.grey, size: 20),
    );
  }
}
