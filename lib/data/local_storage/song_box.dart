import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsius/domain/entities/song_entity.dart';

part 'song_box.g.dart';

@HiveType(typeId: 0)
class SongBox extends HiveObject {
  SongBox();

  @HiveField(0)
  late String id;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String artist;

  @HiveField(3)
  late String album;

  @HiveField(4)
  late int durationMs;

  @HiveField(5)
  late String filePath;

  @HiveField(6)
  late int timestampAdded;

  @HiveField(7)
  int? lastPlayedAt;

  @HiveField(8)
  late int playCount;

  @HiveField(9)
  late bool isFavorite;

  @HiveField(10)
  String? coverArtPath;

  @HiveField(11)
  String? realPath;

  /// Schema version this song was written with. Used for migrations.
  ///
  /// `defaultValue: 0` keeps rows written by builds before field 12 existed
  /// readable — a missing field decodes to 0 (pre-schema) instead of crashing.
  @HiveField(12, defaultValue: 0)
  int schemaVersion = 1;

  SongEntity toEntity() {
    return SongEntity(
      id: id,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      filePath: filePath,
      realPath: realPath,
      coverArtPath: coverArtPath,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(timestampAdded),
      lastPlayedAt: lastPlayedAt,
      playCount: playCount,
      isFavorite: isFavorite,
    );
  }

  factory SongBox.fromEntity(SongEntity entity) {
    final box = SongBox();
    box.id = entity.id;
    box.title = entity.title;
    box.artist = entity.artist;
    box.album = entity.album;
    box.durationMs = entity.durationMs;
    box.filePath = entity.filePath;
    box.realPath = entity.realPath;
    box.coverArtPath = entity.coverArtPath;
    box.timestampAdded = entity.dateAdded?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    box.lastPlayedAt = entity.lastPlayedAt;
    box.playCount = entity.playCount;
    box.isFavorite = entity.isFavorite;
    box.schemaVersion = 1;
    return box;
  }
}
