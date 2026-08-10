class SongEntity {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String filePath;
  final String? realPath;
  final String? coverArtPath;
  final DateTime? dateAdded;
  final int? lastPlayedAt;
  final int playCount;
  final bool isFavorite;

  const SongEntity({
    required this.id,
    required this.title,
    this.artist = 'Unknown Artist',
    this.album = 'Unknown Album',
    this.durationMs = 0,
    required this.filePath,
    this.realPath,
    this.coverArtPath,
    this.dateAdded,
    this.lastPlayedAt,
    this.playCount = 0,
    this.isFavorite = false,
  });

  SongEntity copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? filePath,
    String? realPath,
    String? coverArtPath,
    DateTime? dateAdded,
    int? lastPlayedAt,
    int? playCount,
    bool? isFavorite,
  }) {
    return SongEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      filePath: filePath ?? this.filePath,
      realPath: realPath ?? this.realPath,
      coverArtPath: coverArtPath ?? this.coverArtPath,
      dateAdded: dateAdded ?? this.dateAdded,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playCount: playCount ?? this.playCount,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
