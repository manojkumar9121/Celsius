class PlaylistEntity {
  final String id;
  final String name;
  final String? description;
  final String? coverArtPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> songIds;

  const PlaylistEntity({
    required this.id,
    required this.name,
    this.description,
    this.coverArtPath,
    required this.createdAt,
    required this.updatedAt,
    this.songIds = const [],
  });

  PlaylistEntity copyWith({
    String? name,
    String? description,
    String? coverArtPath,
    List<String>? songIds,
  }) {
    return PlaylistEntity(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverArtPath: coverArtPath ?? this.coverArtPath,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      songIds: songIds ?? this.songIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'coverArtPath': coverArtPath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'songIds': songIds,
    };
  }

  /// Defensive: every field falls back to its default when missing, so
  /// records written by older builds never crash decoding.
  factory PlaylistEntity.fromJson(Map<String, dynamic> json) {
    return PlaylistEntity(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : 'Playlist',
      description: json['description'] is String ? json['description'] as String : null,
      coverArtPath: json['coverArtPath'] is String ? json['coverArtPath'] as String : null,
      createdAt: json['createdAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: json['updatedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch((json['updatedAt'] as num).toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
      songIds: json['songIds'] is List
          ? (json['songIds'] as List).whereType<String>().toList()
          : const [],
    );
  }
}
