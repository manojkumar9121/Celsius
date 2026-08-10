import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/domain/entities/playlist_entity.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';
import 'package:celsuis/data/local_storage/playlist_box.dart';
import 'package:uuid/uuid.dart';

final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>((ref) {
  return PlaylistNotifier();
});

class PlaylistNotifier extends StateNotifier<PlaylistState> {
  PlaylistNotifier() : super(const PlaylistState()) {
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final boxes = HiveStorage.getAllPlaylists();
    state = state.copyWith(
      playlists: boxes.map((box) => box.toEntity()).toList(),
    );
  }

  Future<void> createPlaylist(String name, {String? description}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final playlist = PlaylistBox.fromEntity(PlaylistEntity(
      id: id,
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    ));
    await HiveStorage.addPlaylist(playlist);
    final updated = [...state.playlists, playlist.toEntity()];
    state = state.copyWith(playlists: updated);
  }

  Future<void> deletePlaylist(String id) async {
    await HiveStorage.deletePlaylist(id);
    state = state.copyWith(
      playlists: state.playlists.where((p) => p.id != id).toList(),
    );
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final box = HiveStorage.getPlaylist(id);
    if (box != null) {
      box.name = newName;
      box.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.save();
    }
    final updated = state.playlists.map((p) {
      if (p.id == id) return p.copyWith(name: newName);
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final box = HiveStorage.getPlaylist(playlistId);
    if (box == null) return;
    if (box.songIds.contains(songId)) return;
    box.songIds.add(songId);
    box.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
    await box.save();

    final updated = state.playlists.map((p) {
      if (p.id == playlistId) return p.copyWith(songIds: [...p.songIds, songId]);
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final box = HiveStorage.getPlaylist(playlistId);
    if (box != null) {
      box.songIds.remove(songId);
      box.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.save();
    }
    final updated = state.playlists.map((p) {
      if (p.id == playlistId) return p.copyWith(songIds: p.songIds.where((id) => id != songId).toList());
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
  }

  Future<void> updatePlaylist(String playlistId, {String? name, List<String>? songIds}) async {
    final box = HiveStorage.getPlaylist(playlistId);
    if (box == null) return;
    if (name != null) box.name = name;
    if (songIds != null) {
      box.songIds
        ..clear()
        ..addAll(songIds);
    }
    box.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
    await box.save();

    final updated = state.playlists.map((p) {
      if (p.id == playlistId) return p.copyWith(name: name, songIds: songIds);
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
  }

  Future<void> updatePlaylistCover(String playlistId, String coverPath) async {
    final box = HiveStorage.getPlaylist(playlistId);
    if (box == null) return;
    box.coverArtPath = coverPath;
    box.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
    await box.save();

    final updated = state.playlists.map((p) {
      if (p.id == playlistId) return p.copyWith(coverArtPath: coverPath);
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
  }
}

class PlaylistState {
  final List<PlaylistEntity> playlists;

  const PlaylistState({this.playlists = const []});

  PlaylistState copyWith({List<PlaylistEntity>? playlists}) {
    return PlaylistState(playlists: playlists ?? this.playlists);
  }
}
