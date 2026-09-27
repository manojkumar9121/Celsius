import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsius/domain/entities/app_settings.dart';

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

  // Legacy binary field: no longer mapped (gapless was never wired).
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

  // Legacy binary field: no longer mapped (never wired to audio_service).
  @HiveField(14, defaultValue: true)
  late bool showMediaNotification;

  @HiveField(15, defaultValue: true)
  late bool notificationOngoing;

  @HiveField(16, defaultValue: true)
  late bool stopOnPause;

  @HiveField(17, defaultValue: true)
  late bool autoplayEnabled;

  AppSettings toSettings() {
    final themePresetIndex = themePreset.clamp(0, ThemePreset.values.length - 1);
    final repeatModeIndex = defaultRepeatMode.clamp(0, AppSettingsRepeatMode.values.length - 1);
    final waveformStyleIndex = waveformStyle.clamp(0, WaveformStyle.values.length - 1);
    return AppSettings(
      themePreset: ThemePreset.values[themePresetIndex],
      crossfadeEnabled: crossfadeEnabled,
      crossfadeDurationMs: crossfadeDurationMs,
      defaultRepeatMode: AppSettingsRepeatMode.values[repeatModeIndex],
      defaultShuffle: defaultShuffle,
      autoScanEnabled: autoScanEnabled,
      managedFolders: managedFolders,
      waveformColor: waveformColor,
      waveformStyle: WaveformStyle.values[waveformStyleIndex],
      waveformAnimationSpeed: waveformAnimationSpeed,
      primaryColor: primaryColor,
      accentColor: accentColor,
      notificationOngoing: notificationOngoing,
      stopOnPause: stopOnPause,
      autoplayEnabled: autoplayEnabled,
    );
  }

  factory SettingsBox.fromSettings(AppSettings settings) {
    final box = SettingsBox();
    box.themePreset = settings.themePreset.index;
    box.crossfadeEnabled = settings.crossfadeEnabled;
    box.crossfadeDurationMs = settings.crossfadeDurationMs;
    box.defaultRepeatMode = settings.defaultRepeatMode.index;
    box.defaultShuffle = settings.defaultShuffle;
    box.autoScanEnabled = settings.autoScanEnabled;
    box.managedFolders = settings.managedFolders;
    box.waveformColor = settings.waveformColor;
    box.waveformStyle = settings.waveformStyle.index;
    box.waveformAnimationSpeed = settings.waveformAnimationSpeed;
    box.primaryColor = settings.primaryColor;
    box.accentColor = settings.accentColor;
    // Legacy binary fields must still be initialized: the generated adapter
    // writes them, even though nothing reads them back anymore.
    box.gaplessPlayback = true;
    box.showMediaNotification = true;
    box.notificationOngoing = settings.notificationOngoing;
    box.stopOnPause = settings.stopOnPause;
    box.autoplayEnabled = settings.autoplayEnabled;
    return box;
  }
}
