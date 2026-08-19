// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_box.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsBoxAdapter extends TypeAdapter<SettingsBox> {
  @override
  final int typeId = 2;

  @override
  SettingsBox read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsBox()
      ..themePreset = fields[0] as int
      ..crossfadeEnabled = fields[1] as bool
      ..crossfadeDurationMs = fields[2] as int
      ..gaplessPlayback = fields[3] as bool
      ..defaultRepeatMode = fields[4] as int
      ..defaultShuffle = fields[5] as bool
      ..autoScanEnabled = fields[6] as bool
      ..managedFolders = (fields[7] as List).cast<String>()
      ..waveformColor = fields[8] as String
      ..waveformStyle = fields[9] as int
      ..waveformAnimationSpeed = fields[10] as double
      ..primaryColor = fields[11] as String?
      ..accentColor = fields[12] as String?
      ..showMediaNotification = fields[14] == null ? true : fields[14] as bool
      ..notificationOngoing = fields[15] == null ? true : fields[15] as bool
      ..stopOnPause = fields[16] == null ? true : fields[16] as bool
      ..autoplayEnabled = fields[17] == null ? true : fields[17] as bool;
  }

  @override
  void write(BinaryWriter writer, SettingsBox obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.themePreset)
      ..writeByte(1)
      ..write(obj.crossfadeEnabled)
      ..writeByte(2)
      ..write(obj.crossfadeDurationMs)
      ..writeByte(3)
      ..write(obj.gaplessPlayback)
      ..writeByte(4)
      ..write(obj.defaultRepeatMode)
      ..writeByte(5)
      ..write(obj.defaultShuffle)
      ..writeByte(6)
      ..write(obj.autoScanEnabled)
      ..writeByte(7)
      ..write(obj.managedFolders)
      ..writeByte(8)
      ..write(obj.waveformColor)
      ..writeByte(9)
      ..write(obj.waveformStyle)
      ..writeByte(10)
      ..write(obj.waveformAnimationSpeed)
      ..writeByte(11)
      ..write(obj.primaryColor)
      ..writeByte(12)
      ..write(obj.accentColor)
      ..writeByte(14)
      ..write(obj.showMediaNotification)
      ..writeByte(15)
      ..write(obj.notificationOngoing)
      ..writeByte(16)
      ..write(obj.stopOnPause)
      ..writeByte(17)
      ..write(obj.autoplayEnabled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsBoxAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
