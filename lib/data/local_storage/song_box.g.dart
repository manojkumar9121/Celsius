// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_box.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SongBoxAdapter extends TypeAdapter<SongBox> {
  @override
  final int typeId = 0;

  @override
  SongBox read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SongBox()
      ..id = fields[0] as String
      ..title = fields[1] as String
      ..artist = fields[2] as String
      ..album = fields[3] as String
      ..durationMs = fields[4] as int
      ..filePath = fields[5] as String
      ..timestampAdded = fields[6] as int
      ..lastPlayedAt = fields[7] as int?
      ..playCount = fields[8] as int
      ..isFavorite = fields[9] as bool
      ..coverArtPath = fields[10] as String?
      ..realPath = fields[11] as String?
      ..schemaVersion = fields[12] == null ? 0 : fields[12] as int;
  }

  @override
  void write(BinaryWriter writer, SongBox obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.album)
      ..writeByte(4)
      ..write(obj.durationMs)
      ..writeByte(5)
      ..write(obj.filePath)
      ..writeByte(6)
      ..write(obj.timestampAdded)
      ..writeByte(7)
      ..write(obj.lastPlayedAt)
      ..writeByte(8)
      ..write(obj.playCount)
      ..writeByte(9)
      ..write(obj.isFavorite)
      ..writeByte(10)
      ..write(obj.coverArtPath)
      ..writeByte(11)
      ..write(obj.realPath)
      ..writeByte(12)
      ..write(obj.schemaVersion);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongBoxAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
