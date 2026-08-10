import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsuis/domain/entities/app_settings.dart';

part 'settings_box.g.dart';

@HiveType(typeId: 2)
class SettingsBox extends HiveObject {
  SettingsBox();

  @HiveField(0)
  late int themePreset;

  @HiveField(1)
  late bool crossfadeEnabled;

  @HiveField(2)
  late int crossfadeDurationMs;

  @HiveField(3)
  late bool gaplessPlayback;

  @HiveField(4)
  late int defaultRepeatMode;

  @HiveField(5)
  late bool defaultShuffle;

  @HiveField(6)
  late bool autoScanEnabled;

  @HiveField(7)
  late List<String> managedFolders;

  @HiveField(8)
  late String waveformColor;

  @HiveField(9)
  late int waveformStyle;

  @HiveField(10)
  late double waveformAnimationSpeed;

  @HiveField(11)
  String? primaryColor;

  @HiveField(12)
  String? accentColor;

  @HiveField(14, defaultValue: true)
  late bool showMediaNotification;

  @HiveField(15, defaultValue: true)
  late bool notificationOngoing;

  @HiveField(16, defaultValue: true)
  late bool stopOnPause;

  AppSettings toSettings() {
    final themePresetIndex = themePreset.clamp(0, ThemePreset.values.length - 1);
    final repeatModeIndex = defaultRepeatMode.clamp(0, AppSettingsRepeatMode.values.length - 1);
    final waveformStyleIndex = waveformStyle.clamp(0, WaveformStyle.values.length - 1);
    return AppSettings(
      themePreset: ThemePreset.values[themePresetIndex],
      crossfadeEnabled: crossfadeEnabled,
      crossfadeDurationMs: crossfadeDurationMs,
      gaplessPlayback: gaplessPlayback,
      defaultRepeatMode: AppSettingsRepeatMode.values[repeatModeIndex],
      defaultShuffle: defaultShuffle,
      autoScanEnabled: autoScanEnabled,
      managedFolders: managedFolders,
      waveformColor: waveformColor,
      waveformStyle: WaveformStyle.values[waveformStyleIndex],
      waveformAnimationSpeed: waveformAnimationSpeed,
      primaryColor: primaryColor,
      accentColor: accentColor,
      showMediaNotification: showMediaNotification,
      notificationOngoing: notificationOngoing,
      stopOnPause: stopOnPause,
    );
  }

  factory SettingsBox.fromSettings(AppSettings settings) {
    final box = SettingsBox();
    box.themePreset = settings.themePreset.index;
    box.crossfadeEnabled = settings.crossfadeEnabled;
    box.crossfadeDurationMs = settings.crossfadeDurationMs;
    box.gaplessPlayback = settings.gaplessPlayback;
    box.defaultRepeatMode = settings.defaultRepeatMode.index;
    box.defaultShuffle = settings.defaultShuffle;
    box.autoScanEnabled = settings.autoScanEnabled;
    box.managedFolders = settings.managedFolders;
    box.waveformColor = settings.waveformColor;
    box.waveformStyle = settings.waveformStyle.index;
    box.waveformAnimationSpeed = settings.waveformAnimationSpeed;
    box.primaryColor = settings.primaryColor;
    box.accentColor = settings.accentColor;
    box.showMediaNotification = settings.showMediaNotification;
    box.notificationOngoing = settings.notificationOngoing;
    box.stopOnPause = settings.stopOnPause;
    return box;
  }
}
