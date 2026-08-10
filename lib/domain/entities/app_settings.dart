enum ThemePreset {
  system,
  light,
  dark,
  ocean,
  nord,
  rosePine,
  matrix,
  cyberpunk,
  custom,
}

class AppSettings {
  final ThemePreset themePreset;
  final bool crossfadeEnabled;
  final int crossfadeDurationMs;
  final bool gaplessPlayback;
  final AppSettingsRepeatMode defaultRepeatMode;
  final bool defaultShuffle;
  final bool autoScanEnabled;
  final List<String> managedFolders;
  final String? primaryColor;
  final String? accentColor;
  final String waveformColor;
  final WaveformStyle waveformStyle;
  final double waveformAnimationSpeed;
  final bool showMediaNotification;
  final bool notificationOngoing;
  final bool stopOnPause;

  const AppSettings({
    this.themePreset = ThemePreset.dark,
    this.crossfadeEnabled = false,
    this.crossfadeDurationMs = 300,
    this.gaplessPlayback = true,
    this.defaultRepeatMode = AppSettingsRepeatMode.off,
    this.defaultShuffle = false,
    this.autoScanEnabled = true,
    this.managedFolders = const [],
    this.primaryColor,
    this.accentColor,
    this.waveformColor = '#4ade80',
    this.waveformStyle = WaveformStyle.bars,
    this.waveformAnimationSpeed = 1.0,
    this.showMediaNotification = true,
    this.notificationOngoing = true,
    this.stopOnPause = true,
  });

  AppSettings copyWith({
    ThemePreset? themePreset,
    bool? crossfadeEnabled,
    int? crossfadeDurationMs,
    bool? gaplessPlayback,
    AppSettingsRepeatMode? defaultRepeatMode,
    bool? defaultShuffle,
    bool? autoScanEnabled,
    List<String>? managedFolders,
    String? primaryColor,
    String? accentColor,
    String? waveformColor,
    WaveformStyle? waveformStyle,
    double? waveformAnimationSpeed,
    bool? showMediaNotification,
    bool? notificationOngoing,
    bool? stopOnPause,
  }) {
    return AppSettings(
      themePreset: themePreset ?? this.themePreset,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDurationMs: crossfadeDurationMs ?? this.crossfadeDurationMs,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      defaultRepeatMode: defaultRepeatMode ?? this.defaultRepeatMode,
      defaultShuffle: defaultShuffle ?? this.defaultShuffle,
      autoScanEnabled: autoScanEnabled ?? this.autoScanEnabled,
      managedFolders: managedFolders ?? this.managedFolders,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      waveformColor: waveformColor ?? this.waveformColor,
      waveformStyle: waveformStyle ?? this.waveformStyle,
      waveformAnimationSpeed: waveformAnimationSpeed ?? this.waveformAnimationSpeed,
      showMediaNotification: showMediaNotification ?? this.showMediaNotification,
      notificationOngoing: notificationOngoing ?? this.notificationOngoing,
      stopOnPause: stopOnPause ?? this.stopOnPause,
    );
  }
}

enum AppSettingsRepeatMode { off, one, all }
enum WaveformStyle { bars, line, ribbon, wave, dots, equalizer, blocks, neon, radial }
