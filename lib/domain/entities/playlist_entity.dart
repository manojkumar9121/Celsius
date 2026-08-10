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
}
