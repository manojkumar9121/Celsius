import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsius/domain/entities/playlist_entity.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/data/local_storage/playlist_box.dart';
import 'package:uuid/uuid.dart';

final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>(
  (ref) {
    return PlaylistNotifier();
  },
);

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  PlaylistNotifier({bool autoLoad = true}) : super(const PlaylistState()) {
    if (autoLoad) _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final boxes = HiveStorage.getAllPlaylists();
    state = state.copyWith(
      playlists: boxes.map((box) => box.toEntity()).toList(),
    );
  }

  /// Re-reads playlists from storage. Called after song deletions, which
  /// prune dead ids at the Hive layer, so state never holds stale references.
  Future<void> reload() async {
    if (!mounted) return;
    final boxes = HiveStorage.getAllPlaylists();
    state = state.copyWith(
      playlists: boxes.map((box) => box.toEntity()).toList(),
    );
  }

  Future<void> createPlaylist(String name, {String? description}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final playlist = PlaylistBox.fromEntity(
      PlaylistEntity(
        id: id,
        name: name,
        description: description,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final stored = await HiveStorage.addPlaylist(playlist);
    if (stored == null) throw StateError('Playlist could not be stored');
    state = state.copyWith(playlists: [...state.playlists, stored.toEntity()]);
  }

  Future<void> deletePlaylist(String id) async {
    await HiveStorage.deletePlaylist(id);
    state = state.copyWith(
      playlists: state.playlists.where((p) => p.id != id).toList(),
    );
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final stored = await HiveStorage.renamePlaylist(id, newName);
    if (stored == null) {
      await reload();
      return;
    }
    _replacePlaylist(stored);
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final stored = await HiveStorage.addSongToPlaylist(playlistId, songId);
    if (stored == null) {
      await reload();
      throw StateError('Playlist or song no longer exists');
    }
    _replacePlaylist(stored);
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final stored = await HiveStorage.removeSongFromPlaylist(playlistId, songId);
    if (stored == null) {
      await reload();
      return;
    }
    _replacePlaylist(stored);
  }

  Future<void> reorderPlaylistSongs(
    String playlistId,
    List<String> orderedIds,
  ) async {
    final stored = await HiveStorage.reorderPlaylistSongs(
      playlistId,
      orderedIds,
    );
    if (stored == null) {
      await reload();
      return;
    }
    _replacePlaylist(stored);
  }

  Future<void> updatePlaylistCover(String playlistId, String coverPath) async {
    final stored = await HiveStorage.setPlaylistCoverArt(playlistId, coverPath);
    if (stored == null) {
      await reload();
      return;
    }
    _replacePlaylist(stored);
  }

  void _replacePlaylist(PlaylistBox playlist) {
    var replaced = false;
    final playlists = [
      for (final existing in state.playlists)
        if (existing.id == playlist.id) playlist.toEntity() else existing,
    ];
    for (var i = 0; i < playlists.length; i++) {
      if (playlists[i].id == playlist.id) {
        replaced = true;
        break;
      }
    }
    if (!replaced) playlists.add(playlist.toEntity());
    state = state.copyWith(playlists: playlists);
  }
}

class PlaylistState {
  final List<PlaylistEntity> playlists;

  const PlaylistState({this.playlists = const []});

  PlaylistState copyWith({List<PlaylistEntity>? playlists}) {
    return PlaylistState(playlists: playlists ?? this.playlists);
  }
}
