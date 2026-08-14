import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsuis/domain/entities/playlist_entity.dart';

part 'playlist_box.g.dart';

@HiveType(typeId: 1)
class PlaylistBox extends HiveObject {
  PlaylistBox();

  @HiveField(0)
  String id = '';

  @HiveField(1)
  String name = '';

  @HiveField(2)
  String? description;

  @HiveField(3)
  String? coverArtPath;

  @HiveField(4)
  int timestampCreated = DateTime.now().millisecondsSinceEpoch;

  @HiveField(5)
  int timestampUpdated = DateTime.now().millisecondsSinceEpoch;

  @HiveField(6)
  List<String> songIds = const [];

  /// Automatically sets [coverArtPath] to the first song's artwork if not already set.
  void autoSetCoverArt(String? firstSongCoverArtPath) {
    if (coverArtPath == null || coverArtPath!.isEmpty) {
      coverArtPath = firstSongCoverArtPath;
      timestampUpdated = DateTime.now().millisecondsSinceEpoch;
    }
  }

  PlaylistEntity toEntity() {
    return PlaylistEntity(
      id: id,
      name: name,
      description: description,
      coverArtPath: coverArtPath,
      createdAt: DateTime.fromMillisecondsSinceEpoch(timestampCreated),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(timestampUpdated),
      songIds: List.from(songIds),
    );
  }

  factory PlaylistBox.fromEntity(PlaylistEntity entity) {
    final box = PlaylistBox();
    box.id = entity.id;
    box.name = entity.name;
    box.description = entity.description;
    box.coverArtPath = entity.coverArtPath;
    box.timestampCreated = entity.createdAt.millisecondsSinceEpoch;
    box.timestampUpdated = entity.updatedAt.millisecondsSinceEpoch;
    box.songIds = List.from(entity.songIds);
    return box;
  }
}
