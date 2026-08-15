import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/presentation/widgets/song_tile.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:celsuis/domain/entities/playlist_entity.dart';
import 'package:file_picker/file_picker.dart';
import 'package:celsuis/core/widgets/cached_song_image.dart';
import 'package:celsuis/core/widgets/create_playlist_dialog.dart';
import 'package:celsuis/core/widgets/shimmer.dart';

enum SongSortField { title, artist, album, dateAdded, duration }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _currentTab = 'songs';
  bool _isGridView = false;
  SongSortField _sortField = SongSortField.title;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      final tabs = ['songs', 'albums', 'artists', 'playlists'];
      setState(() {
        _currentTab = tabs[_tabController.index];
        _isGridView = false;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final playlistState = ref.watch(playlistProvider);
    final currentSong = ref.watch(audioPlayerProvider).currentSong;
    final colorScheme = Theme.of(context).colorScheme;

    final filteredSongs = libraryState.searchQuery.isNotEmpty ||
        libraryState.selectedAlbum.isNotEmpty ||
        libraryState.selectedArtist.isNotEmpty
        ? ref.read(libraryProvider.notifier).filteredSongs
        : libraryState.songs;

    final sortedSongs = _sortSongs(filteredSongs);

    final albumGroups = _currentTab == 'albums'
        ? ref.read(libraryProvider.notifier).songsByAlbum
        : <String, List<SongEntity>>{};
    final artistGroups = _currentTab == 'artists'
        ? ref.read(libraryProvider.notifier).songsByArtist
        : <String, List<SongEntity>>{};

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search songs',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (query) => ref.read(libraryProvider.notifier).setSearchQuery(query),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_currentTab == 'songs' && sortedSongs.isNotEmpty)
                    PopupMenuButton<SongSortField>(
                      icon: Icon(Icons.sort, color: colorScheme.onSurface),
                      onSelected: (field) {
                        setState(() {
                          if (_sortField == field) {
                            _sortAscending = !_sortAscending;
                          } else {
                            _sortField = field;
                            _sortAscending = true;
                          }
                        });
                      },
                      itemBuilder: (ctx) => [
                        _sortItem(SongSortField.title, 'Title'),
                        _sortItem(SongSortField.artist, 'Artist'),
                        _sortItem(SongSortField.album, 'Album'),
                        _sortItem(SongSortField.dateAdded, 'Date Added'),
                        _sortItem(SongSortField.duration, 'Duration'),
                      ],
                    ),
                  if (_currentTab != 'songs' && _currentTab != 'playlists')
                    IconButton(
                      icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                      onPressed: () => setState(() => _isGridView = !_isGridView),
                      tooltip: _isGridView ? 'List view' : 'Grid view',
                    ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Songs'),
                Tab(text: 'Albums'),
                Tab(text: 'Artists'),
                Tab(text: 'Playlists'),
              ],
            ),
            if (libraryState.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  color: colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            libraryState.error!,
                            style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (libraryState.isScanning)
              LinearProgressIndicator(value: libraryState.scanningProgress)
            else if (libraryState.isLoading)
              Expanded(
                child: ListView.builder(
                  itemCount: 10,
                  itemBuilder: (ctx, index) => const ShimmerSongTile(),
                ),
              )
            else
              Expanded(
                child: _currentTab == 'songs'
                    ? _buildSongList(sortedSongs, currentSong)
                    : _currentTab == 'albums'
                        ? _buildAlbumView(albumGroups, currentSong)
                        : _currentTab == 'artists'
                            ? _buildArtistView(artistGroups, currentSong)
                            : _buildPlaylistList(playlistState.playlists),
              ),
          ],
        ),
      ),
      floatingActionButton: (_currentTab == 'playlists')
          ? FloatingActionButton(
              onPressed: () async {
                await HapticFeedback.lightImpact();
                if (!context.mounted) return;
                await showCreatePlaylistDialog(context, ref);
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  PopupMenuItem<SongSortField> _sortItem(SongSortField field, String label) {
    return PopupMenuItem(
      value: field,
      child: Row(
        children: [
          Text(label),
          if (_sortField == field)
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  List<SongEntity> _sortSongs(List<SongEntity> songs) {
    final sorted = List<SongEntity>.from(songs);
    sorted.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case SongSortField.title:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case SongSortField.artist:
          cmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case SongSortField.album:
          cmp = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          break;
        case SongSortField.dateAdded:
          final aDate = a.dateAdded ?? DateTime(0);
          final bDate = b.dateAdded ?? DateTime(0);
          cmp = aDate.compareTo(bDate);
          break;
        case SongSortField.duration:
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  Widget _buildSongList(List<SongEntity> songs, SongEntity? currentSong) {
    if (songs.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: const AlwaysStoppedAnimation<double>(0),
              builder: (context, child) {
                return Icon(
                  Icons.library_music_outlined,
                  size: 72,
                  color: colorScheme.primary.withValues(alpha: 0.5),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'No songs in library',
              style: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a folder to scan for music',
              style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await HapticFeedback.mediumImpact();
                final path = await FilePicker.platform.getDirectoryPath();
                if (path != null && mounted) {
                  ref.read(libraryProvider.notifier).scanFolder(path);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Music'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isPlaying = currentSong?.id == song.id;
        return SongTile(
          song: song,
          isPlaying: isPlaying,
          onTap: () async {
            await HapticFeedback.lightImpact();
            ref.read(audioPlayerProvider.notifier).playSong(song, songs);
            if (!context.mounted) return;
            context.push('/now-playing');
          },
        );
      },
    );
  }

  Widget _buildAlbumView(Map<String, List<SongEntity>> albumGroups, SongEntity? currentSong) {
    if (albumGroups.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 64, color: colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No albums found', style: TextStyle(color: colorScheme.onSurface, fontSize: 16)),
          ],
        ),
      );
    }
    if (_isGridView) {
      return _buildAlbumGrid(albumGroups, currentSong);
    }
    return _buildAlbumList(albumGroups, currentSong);
  }

  Widget _buildAlbumList(Map<String, List<SongEntity>> albumGroups, SongEntity? currentSong) {
    return ListView.builder(
      itemCount: albumGroups.length,
      itemBuilder: (context, index) {
        final album = albumGroups.keys.elementAt(index);
        final songs = albumGroups[album]!;
        return ExpansionTile(
          leading: _buildAlbumArt(songs.first),
          title: Text(album, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${songs.length} songs'),
          children: songs.map((song) {
            final isPlaying = currentSong?.id == song.id;
            return SongTile(
              song: song,
              isPlaying: isPlaying,
              onTap: () async {
                await HapticFeedback.lightImpact();
                ref.read(audioPlayerProvider.notifier).playSong(song, songs);
                if (!context.mounted) return;
                context.push('/now-playing');
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAlbumGrid(Map<String, List<SongEntity>> albumGroups, SongEntity? currentSong) {
    final albums = albumGroups.keys.toList();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final songs = albumGroups[album]!;
        return GestureDetector(
          onTap: () async {
            await HapticFeedback.lightImpact();
            ref.read(audioPlayerProvider.notifier).playSong(songs.first, songs);
            if (!context.mounted) return;
            context.push('/now-playing');
          },
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: _buildAlbumArt(songs.first, size: double.infinity),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                '${songs.length} songs',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtistView(Map<String, List<SongEntity>> artistGroups, SongEntity? currentSong) {
    if (artistGroups.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 64, color: colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No artists found', style: TextStyle(color: colorScheme.onSurface, fontSize: 16)),
          ],
        ),
      );
    }
    if (_isGridView) {
      return _buildArtistGrid(artistGroups, currentSong);
    }
    return _buildArtistList(artistGroups, currentSong);
  }

  Widget _buildArtistList(Map<String, List<SongEntity>> artistGroups, SongEntity? currentSong) {
    return ListView.builder(
      itemCount: artistGroups.length,
      itemBuilder: (context, index) {
        final artist = artistGroups.keys.elementAt(index);
        final songs = artistGroups[artist]!;
        return ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              artist.isNotEmpty ? artist[0].toUpperCase() : '?',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${songs.length} songs'),
          children: songs.map((song) {
            final isPlaying = currentSong?.id == song.id;
            return SongTile(
              song: song,
              isPlaying: isPlaying,
              onTap: () async {
                await HapticFeedback.lightImpact();
                ref.read(audioPlayerProvider.notifier).playSong(song, songs);
                if (!context.mounted) return;
                context.push('/now-playing');
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildArtistGrid(Map<String, List<SongEntity>> artistGroups, SongEntity? currentSong) {
    final artists = artistGroups.keys.toList();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final songs = artistGroups[artist]!;
        return GestureDetector(
          onTap: () async {
            await HapticFeedback.lightImpact();
            ref.read(audioPlayerProvider.notifier).playSong(songs.first, songs);
            if (!context.mounted) return;
            context.push('/now-playing');
          },
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Center(
                    child: Text(
                      artist.isNotEmpty ? artist[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                artist,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                '${songs.length} songs',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaylistList(List<PlaylistEntity> playlists) {
    if (playlists.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: const AlwaysStoppedAnimation<double>(0),
              builder: (context, child) {
                return Icon(
                  Icons.playlist_play,
                  size: 64,
                  color: colorScheme.primary.withValues(alpha: 0.5),
                );
              },
            ),
            const SizedBox(height: 16),
            Text('No playlists yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await HapticFeedback.mediumImpact();
                if (!mounted) return;
                await showCreatePlaylistDialog(context, ref);
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Playlist'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: playlist.coverArtPath != null && playlist.coverArtPath!.isNotEmpty && File(playlist.coverArtPath!).existsSync()
                ? Image.file(File(playlist.coverArtPath!), fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.secondary,
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.queue_music, color: Colors.white, size: 24),
                    ),
                  ),
          ),
          title: Text(playlist.name),
          subtitle: Text('${playlist.songIds.length} songs'),
          trailing: PopupMenuButton(
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
            ],
            onSelected: (value) {
              if (value == 'delete') {
                ref.read(playlistProvider.notifier).deletePlaylist(playlist.id);
              } else if (value == 'rename') {
                _showRenamePlaylistDialog(playlist);
              }
            },
          ),
          onTap: () => context.push('/playlist/${playlist.id}'),
        );
      },
    );
  }

  Widget _buildAlbumArt(SongEntity song, {double size = 40}) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: SongCoverImage(
          coverArtPath: song.coverArtPath,
          width: size,
          height: size,
          borderRadius: size / 2,
          placeholderBuilder: (_, w, h) => _albumPlaceholder(w, h),
        ),
      ),
    );
  }

  Widget _albumPlaceholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.music_note, color: Colors.grey, size: 24),
    );
  }

  void _showRenamePlaylistDialog(PlaylistEntity playlist) {
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
}
