// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_box.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlaylistBoxAdapter extends TypeAdapter<PlaylistBox> {
  @override
  final int typeId = 1;

  @override
  PlaylistBox read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaylistBox()
      ..id = fields[0] as String
      ..name = fields[1] as String
      ..description = fields[2] as String?
      ..coverArtPath = fields[3] as String?
      ..timestampCreated = fields[4] as int
      ..timestampUpdated = fields[5] as int
      ..songIds = (fields[6] as List).cast<String>();
  }

  @override
  void write(BinaryWriter writer, PlaylistBox obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.coverArtPath)
      ..writeByte(4)
      ..write(obj.timestampCreated)
      ..writeByte(5)
      ..write(obj.timestampUpdated)
      ..writeByte(6)
      ..write(obj.songIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistBoxAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
