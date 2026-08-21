/// Skins for the Now Playing screen. [classic] is the original dark +
/// dominant-color design and remains the default.
///
/// Values are persisted by index — only ever APPEND new skins.
enum NowPlayingTheme {
  classic,
  risoZine,
  paperPress,
  pocketLcd,
  concrete,
  sumi,
  concreteNoir,
  sumiNight,
}

/// App-wide color presets. The zine/LCD presets mirror the matching
/// [NowPlayingTheme] skins (and auto-select them when chosen). Values are
/// persisted by index — keep the order stable and only APPEND new presets.
enum ThemePreset {
  system,
  light,
  dark,
  risoZine,
  nord,
  paperPress,
  matrix,
  pocketLcd,
  custom,
  concrete,
  sumi,
  concreteNoir,
  sumiNight,
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
  final NowPlayingTheme nowPlayingTheme;
  final bool showMediaNotification;
  final bool notificationOngoing;
  final bool stopOnPause;
  final bool autoplayEnabled;

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
    this.nowPlayingTheme = NowPlayingTheme.classic,
    this.showMediaNotification = true,
    this.notificationOngoing = true,
    this.stopOnPause = true,
    this.autoplayEnabled = true,
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
    NowPlayingTheme? nowPlayingTheme,
    bool? showMediaNotification,
    bool? notificationOngoing,
    bool? stopOnPause,
    bool? autoplayEnabled,
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
      nowPlayingTheme: nowPlayingTheme ?? this.nowPlayingTheme,
      showMediaNotification: showMediaNotification ?? this.showMediaNotification,
      notificationOngoing: notificationOngoing ?? this.notificationOngoing,
      stopOnPause: stopOnPause ?? this.stopOnPause,
      autoplayEnabled: autoplayEnabled ?? this.autoplayEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themePreset': themePreset.index,
      'crossfadeEnabled': crossfadeEnabled,
      'crossfadeDurationMs': crossfadeDurationMs,
      'gaplessPlayback': gaplessPlayback,
      'defaultRepeatMode': defaultRepeatMode.index,
      'defaultShuffle': defaultShuffle,
      'autoScanEnabled': autoScanEnabled,
      'managedFolders': managedFolders,
      'primaryColor': primaryColor,
      'accentColor': accentColor,
      'waveformColor': waveformColor,
      'waveformStyle': waveformStyle.index,
      'waveformAnimationSpeed': waveformAnimationSpeed,
      'nowPlayingTheme': nowPlayingTheme.index,
      'showMediaNotification': showMediaNotification,
      'notificationOngoing': notificationOngoing,
      'stopOnPause': stopOnPause,
      'autoplayEnabled': autoplayEnabled,
    };
  }

  /// Defensive: every field falls back to its default when missing or
  /// wrong-typed, so records written by older builds (or with a future
  /// schema) never crash decoding.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themePreset: _enumFromIndex<ThemePreset>(json['themePreset'], ThemePreset.values, ThemePreset.dark),
      crossfadeEnabled: json['crossfadeEnabled'] == true,
      crossfadeDurationMs: json['crossfadeDurationMs'] is num
          ? (json['crossfadeDurationMs'] as num).toInt()
          : 300,
      gaplessPlayback: json['gaplessPlayback'] != false,
      defaultRepeatMode: _enumFromIndex<AppSettingsRepeatMode>(
          json['defaultRepeatMode'], AppSettingsRepeatMode.values, AppSettingsRepeatMode.off),
      defaultShuffle: json['defaultShuffle'] == true,
      autoScanEnabled: json['autoScanEnabled'] != false,
      managedFolders: json['managedFolders'] is List
          ? (json['managedFolders'] as List).whereType<String>().toList()
          : const [],
      primaryColor: json['primaryColor'] is String ? json['primaryColor'] as String : null,
      accentColor: json['accentColor'] is String ? json['accentColor'] as String : null,
      waveformColor: json['waveformColor'] is String ? json['waveformColor'] as String : '#4ade80',
      waveformStyle: _enumFromIndex<WaveformStyle>(json['waveformStyle'], WaveformStyle.values, WaveformStyle.bars),
      waveformAnimationSpeed: json['waveformAnimationSpeed'] is num
          ? (json['waveformAnimationSpeed'] as num).toDouble()
          : 1.0,
      nowPlayingTheme: _enumFromIndex<NowPlayingTheme>(
          json['nowPlayingTheme'], NowPlayingTheme.values, NowPlayingTheme.classic),
      showMediaNotification: json['showMediaNotification'] != false,
      notificationOngoing: json['notificationOngoing'] != false,
      stopOnPause: json['stopOnPause'] != false,
      autoplayEnabled: json['autoplayEnabled'] != false,
    );
  }

  /// Reads an enum from a stored index; clamps out-of-range values and falls
  /// back to [fallback] for missing/wrong-typed data.
  static T _enumFromIndex<T>(dynamic value, List<T> values, T fallback) {
    if (value is! num) return fallback;
    final index = value.toInt();
    if (index < 0 || index >= values.length) return fallback;
    return values[index];
  }
}

enum AppSettingsRepeatMode { off, one, all }
enum WaveformStyle { bars, line, ribbon, wave, dots, equalizer, blocks, neon, radial }
