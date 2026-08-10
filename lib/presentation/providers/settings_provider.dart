import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';
import 'package:celsuis/core/utils/color_utils.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider);
  switch (settings.themePreset) {
    case ThemePreset.system:
      return ThemeMode.system;
    case ThemePreset.custom:
      // custom theme is always built as a dark ThemeData (see _customTheme);
      // forcing system mode would fall back to the default light theme on
      // light-mode devices and make the chosen color look "forgotten".
      return ThemeMode.dark;
    case ThemePreset.light:
      return ThemeMode.light;
    case ThemePreset.dark:
    case ThemePreset.ocean:
    case ThemePreset.nord:
    case ThemePreset.rosePine:
    case ThemePreset.matrix:
    case ThemePreset.cyberpunk:
      return ThemeMode.dark;
  }
});

final currentThemeProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(settingsProvider);
  return _buildThemeData(settings);
});

ThemeData _buildThemeData(AppSettings settings) {
  if (settings.themePreset == ThemePreset.custom && settings.primaryColor != null) {
    return _customTheme(settings.primaryColor!, settings.accentColor);
  }
  switch (settings.themePreset) {
    case ThemePreset.light:
      return _lightTheme;
    case ThemePreset.ocean:
      return _oceanTheme;
    case ThemePreset.nord:
      return _nordTheme;
    case ThemePreset.rosePine:
      return _rosePineTheme;
    case ThemePreset.matrix:
      return _matrixTheme;
    case ThemePreset.cyberpunk:
      return _cyberpunkTheme;
    default:
      return _darkTheme;
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(HiveStorage.getSettings());

  void updateSettings(AppSettings newSettings) {
    state = newSettings;
    HiveStorage.saveSettings(newSettings);
  }

  void setThemePreset(ThemePreset preset) {
    state = state.copyWith(themePreset: preset);
    HiveStorage.saveSettings(state);
  }

  void setPrimaryColor(Color color) {
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    state = state.copyWith(
      primaryColor: hex,
      themePreset: ThemePreset.custom,
    );
    HiveStorage.saveSettings(state);
  }

  void setAccentColor(Color color) {
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    state = state.copyWith(accentColor: hex);
    HiveStorage.saveSettings(state);
  }

  void toggleCrossfade(bool value) {
    state = state.copyWith(crossfadeEnabled: value);
    HiveStorage.saveSettings(state);
  }

  void setCrossfadeDuration(int ms) {
    state = state.copyWith(crossfadeDurationMs: ms);
    HiveStorage.saveSettings(state);
  }

  void toggleGaplessPlayback(bool value) {
    state = state.copyWith(gaplessPlayback: value);
    HiveStorage.saveSettings(state);
  }

  void setRepeatMode(AppSettingsRepeatMode mode) {
    state = state.copyWith(defaultRepeatMode: mode);
    HiveStorage.saveSettings(state);
  }

  void toggleShuffle(bool value) {
    state = state.copyWith(defaultShuffle: value);
    HiveStorage.saveSettings(state);
  }

  void setWaveformStyle(WaveformStyle style) {
    state = state.copyWith(waveformStyle: style);
    HiveStorage.saveSettings(state);
  }

  void setWaveformColor(Color color) {
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    state = state.copyWith(waveformColor: hex);
    HiveStorage.saveSettings(state);
  }

  void setWaveformAnimationSpeed(double speed) {
    state = state.copyWith(waveformAnimationSpeed: speed);
    HiveStorage.saveSettings(state);
  }

  void toggleAutoScan(bool value) {
    state = state.copyWith(autoScanEnabled: value);
    HiveStorage.saveSettings(state);
  }

  void toggleMediaNotification(bool value) {
    state = state.copyWith(showMediaNotification: value);
    HiveStorage.saveSettings(state);
  }

  void toggleNotificationOngoing(bool value) {
    state = state.copyWith(notificationOngoing: value);
    HiveStorage.saveSettings(state);
  }

  void toggleStopOnPause(bool value) {
    state = state.copyWith(stopOnPause: value);
    HiveStorage.saveSettings(state);
  }

  Future<void> removeManagedFolder(String path) async {
    await HiveStorage.removeManagedFolder(path);
    state = HiveStorage.getSettings();
  }
}

ThemeData _customTheme(String primaryHex, String? accentHex) {
  final color = parseHexColor(primaryHex);
  final accent = accentHex != null && accentHex.isNotEmpty
      ? parseHexColor(accentHex)
      : color;
  return ThemeData.dark().copyWith(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: color,
      secondary: accent,
      tertiary: accent,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF121212)),
    cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
  );
}



final _lightTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(primary: Color(0xFF1DB954)),
  scaffoldBackgroundColor: const Color(0xFFF5F5F5),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFFF5F5F5)),
  cardTheme: const CardThemeData(color: Color(0xFFFFFFFF)),
);

final _darkTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(primary: Color(0xFF1DB954)),
  scaffoldBackgroundColor: const Color(0xFF121212),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF121212)),
  cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
);

final _oceanTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(primary: Color(0xFF4facfe), secondary: Color(0xFF00f2fe)),
  scaffoldBackgroundColor: const Color(0xFF0d2b45),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF0d2b45)),
  cardTheme: const CardThemeData(color: Color(0xFF1a3a5c)),
);

final _nordTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(primary: Color(0xFF88C0D0), secondary: Color(0xFF81A1C1)),
  scaffoldBackgroundColor: const Color(0xFF2E3440),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF2E3440)),
  cardTheme: const CardThemeData(color: Color(0xFF3B4252)),
);

final _rosePineTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(primary: Color(0xFFEA9A97), secondary: Color(0xFFD9D9D9)),
  scaffoldBackgroundColor: const Color(0xFF1F1821),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF1F1821)),
  cardTheme: const CardThemeData(color: Color(0xFF261F28)),
);

final _matrixTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF00FF41),
    secondary: Color(0xFF00CC33),
    surface: Color(0xFF001a00),
  ),
  scaffoldBackgroundColor: const Color(0xFF000a00),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF000a00)),
  cardTheme: const CardThemeData(color: Color(0xFF001a00)),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFF00FF41), fontFamily: 'monospace'),
    bodyMedium: TextStyle(color: Color(0xFF00FF41), fontFamily: 'monospace'),
    bodySmall: TextStyle(color: Color(0xFF00CC33), fontFamily: 'monospace'),
    titleLarge: TextStyle(color: Color(0xFF00FF41), fontFamily: 'monospace'),
    titleMedium: TextStyle(color: Color(0xFF00FF41), fontFamily: 'monospace'),
  ),
  iconTheme: const IconThemeData(color: Color(0xFF00FF41)),
  listTileTheme: const ListTileThemeData(
    textColor: Color(0xFF00FF41),
    iconColor: Color(0xFF00CC33),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF000a00),
    foregroundColor: Color(0xFF00FF41),
    elevation: 0,
  ),
);

final _cyberpunkTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFFF0090),
    secondary: Color(0xFF00F0FF),
    surface: Color(0xFF120025),
  ),
  scaffoldBackgroundColor: const Color(0xFF0a0012),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF0a0012)),
  cardTheme: const CardThemeData(color: Color(0xFF180030)),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFFFF0090)),
    bodyMedium: TextStyle(color: Color(0xFFFF0090)),
    bodySmall: TextStyle(color: Color(0xFF00F0FF)),
    titleLarge: TextStyle(color: Color(0xFFFF0090)),
    titleMedium: TextStyle(color: Color(0xFFFF0090)),
  ),
  iconTheme: const IconThemeData(color: Color(0xFF00F0FF)),
  listTileTheme: const ListTileThemeData(
    textColor: Color(0xFFFF0090),
    iconColor: Color(0xFF00F0FF),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0a0012),
    foregroundColor: Color(0xFFFF0090),
    elevation: 0,
  ),
);
