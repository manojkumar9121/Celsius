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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'filePath': filePath,
      'realPath': realPath,
      'coverArtPath': coverArtPath,
      'dateAdded': dateAdded?.millisecondsSinceEpoch,
      'lastPlayedAt': lastPlayedAt,
      'playCount': playCount,
      'isFavorite': isFavorite,
    };
  }

  /// Defensive: every field falls back to its default when missing, so
  /// records written by older builds (or with future fields absent) never
  /// crash decoding.
  factory SongEntity.fromJson(Map<String, dynamic> json) {
    final dateAddedMs = json['dateAdded'];
    return SongEntity(
      id: json['id'] is String ? json['id'] as String : '',
      title: json['title'] is String ? json['title'] as String : 'Unknown Title',
      artist: json['artist'] is String ? json['artist'] as String : 'Unknown Artist',
      album: json['album'] is String ? json['album'] as String : 'Unknown Album',
      durationMs: json['durationMs'] is num ? (json['durationMs'] as num).toInt() : 0,
      filePath: json['filePath'] is String ? json['filePath'] as String : '',
      realPath: json['realPath'] is String ? json['realPath'] as String : null,
      coverArtPath: json['coverArtPath'] is String ? json['coverArtPath'] as String : null,
      dateAdded: dateAddedMs is num
          ? DateTime.fromMillisecondsSinceEpoch(dateAddedMs.toInt())
          : null,
      lastPlayedAt: json['lastPlayedAt'] is num ? (json['lastPlayedAt'] as num).toInt() : null,
      playCount: json['playCount'] is num ? (json['playCount'] as num).toInt() : 0,
      isFavorite: json['isFavorite'] == true,
    );
  }
}
