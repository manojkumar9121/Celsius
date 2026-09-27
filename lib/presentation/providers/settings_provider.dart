import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/core/utils/color_utils.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
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
    case ThemePreset.risoZine:
    case ThemePreset.paperPress:
    case ThemePreset.pocketLcd:
    case ThemePreset.concrete:
    case ThemePreset.sumi:
      return ThemeMode.light;
    case ThemePreset.dark:
    case ThemePreset.nord:
    case ThemePreset.matrix:
    case ThemePreset.concreteNoir:
    case ThemePreset.sumiNight:
      return ThemeMode.dark;
  }
});

final currentThemeProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(settingsProvider);
  return _buildThemeData(settings);
});

ThemeData _buildThemeData(AppSettings settings) {
  if (settings.themePreset == ThemePreset.custom &&
      settings.primaryColor != null) {
    return _customTheme(settings.primaryColor!, settings.accentColor);
  }
  switch (settings.themePreset) {
    case ThemePreset.light:
      return _lightTheme;
    case ThemePreset.risoZine:
      return _risoZineTheme;
    case ThemePreset.nord:
      return _nordTheme;
    case ThemePreset.paperPress:
      return _paperPressTheme;
    case ThemePreset.matrix:
      return _matrixTheme;
    case ThemePreset.pocketLcd:
      return _pocketLcdTheme;
    case ThemePreset.concrete:
      return _concreteTheme;
    case ThemePreset.sumi:
      return _sumiTheme;
    case ThemePreset.concreteNoir:
      return _concreteNoirTheme;
    case ThemePreset.sumiNight:
      return _sumiNightTheme;
    default:
      return _darkTheme;
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(HiveStorage.getSettings());

  /// Applies a field-specific change to the latest persisted settings. The
  /// shared Hive queue orders rapid changes, and state is published only after
  /// the corresponding write succeeds so runtime listeners receive a committed
  /// snapshot rather than an optimistic value that storage has not accepted.
  Future<void> _mutate(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final committed = await HiveStorage.mutateSettings(transform);
    if (mounted) state = committed;
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    final committed = await HiveStorage.saveSettings(newSettings);
    if (mounted) state = committed;
  }

  Future<void> setThemePreset(ThemePreset preset) {
    return _mutate((current) {
      final matchingTheme = _matchingNowPlayingTheme(preset);
      return current.copyWith(
        themePreset: preset,
        nowPlayingTheme: matchingTheme ?? current.nowPlayingTheme,
      );
    });
  }

  /// The Now Playing skin paired with [preset], or null when the preset has
  /// no matching skin (classic remains whatever the user chose).
  static NowPlayingTheme? _matchingNowPlayingTheme(ThemePreset preset) {
    switch (preset) {
      case ThemePreset.risoZine:
        return NowPlayingTheme.risoZine;
      case ThemePreset.paperPress:
        return NowPlayingTheme.paperPress;
      case ThemePreset.pocketLcd:
        return NowPlayingTheme.pocketLcd;
      case ThemePreset.concrete:
        return NowPlayingTheme.concrete;
      case ThemePreset.sumi:
        return NowPlayingTheme.sumi;
      case ThemePreset.concreteNoir:
        return NowPlayingTheme.concreteNoir;
      case ThemePreset.sumiNight:
        return NowPlayingTheme.sumiNight;
      default:
        return null;
    }
  }

  Future<void> setPrimaryColor(Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return _mutate(
      (current) =>
          current.copyWith(primaryColor: hex, themePreset: ThemePreset.custom),
    );
  }

  Future<void> setAccentColor(Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return _mutate((current) => current.copyWith(accentColor: hex));
  }

  Future<void> toggleCrossfade(bool value) {
    return _mutate((current) => current.copyWith(crossfadeEnabled: value));
  }

  Future<void> setCrossfadeDuration(int ms) {
    return _mutate((current) => current.copyWith(crossfadeDurationMs: ms));
  }

  Future<void> setRepeatMode(AppSettingsRepeatMode mode) {
    return _mutate((current) => current.copyWith(defaultRepeatMode: mode));
  }

  Future<void> toggleShuffle(bool value) {
    return _mutate((current) => current.copyWith(defaultShuffle: value));
  }

  Future<void> setWaveformStyle(WaveformStyle style) {
    return _mutate((current) => current.copyWith(waveformStyle: style));
  }

  Future<void> setWaveformColor(Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return _mutate((current) => current.copyWith(waveformColor: hex));
  }

  Future<void> setWaveformAnimationSpeed(double speed) {
    return _mutate(
      (current) => current.copyWith(waveformAnimationSpeed: speed),
    );
  }

  Future<void> setNowPlayingTheme(NowPlayingTheme theme) {
    return _mutate((current) => current.copyWith(nowPlayingTheme: theme));
  }

  Future<void> toggleAutoScan(bool value) {
    return _mutate((current) => current.copyWith(autoScanEnabled: value));
  }

  Future<void> toggleNotificationOngoing(bool value) {
    return _mutate((current) => current.copyWith(notificationOngoing: value));
  }

  Future<void> toggleStopOnPause(bool value) {
    return _mutate((current) => current.copyWith(stopOnPause: value));
  }

  Future<void> toggleAutoplay(bool value) {
    return _mutate((current) => current.copyWith(autoplayEnabled: value));
  }

  Future<void> addManagedFolder(String path) async {
    final committed = await HiveStorage.addManagedFolder(path);
    if (mounted) state = committed;
  }

  Future<void> removeManagedFolder(String path) async {
    final committed = await HiveStorage.removeManagedFolder(path);
    if (mounted) state = committed;
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
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF121212),
    ),
    cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
  );
}

final _lightTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(primary: Color(0xFF1DB954)),
  scaffoldBackgroundColor: const Color(0xFFF5F5F5),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFFF5F5F5),
  ),
  cardTheme: const CardThemeData(color: Color(0xFFFFFFFF)),
);

final _darkTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(primary: Color(0xFF1DB954)),
  scaffoldBackgroundColor: const Color(0xFF121212),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFF121212),
  ),
  cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
);

/// Riso Zine: cream paper, blue + pink risograph inks.
final _risoZineTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF0078BF),
    secondary: Color(0xFFFF48B0),
    tertiary: Color(0xFF16151A),
  ),
  scaffoldBackgroundColor: const Color(0xFFF5F1E8),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFFF5F1E8),
  ),
  cardTheme: const CardThemeData(color: Color(0xFFFFFFFF)),
);

final _nordTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF88C0D0),
    secondary: Color(0xFF81A1C1),
  ),
  scaffoldBackgroundColor: const Color(0xFF2E3440),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFF2E3440),
  ),
  cardTheme: const CardThemeData(color: Color(0xFF3B4252)),
);

/// Paper Press: warm paper cream, brick-red ink.
final _paperPressTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFFC2452D),
    secondary: Color(0xFF1C1A17),
  ),
  scaffoldBackgroundColor: const Color(0xFFF2EFE6),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFFF2EFE6),
  ),
  cardTheme: const CardThemeData(color: Color(0xFFFFFFFF)),
);

final _matrixTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF00FF41),
    secondary: Color(0xFF00CC33),
    surface: Color(0xFF001a00),
  ),
  scaffoldBackgroundColor: const Color(0xFF000a00),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFF000a00),
  ),
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

/// Pocket LCD: olive screen, dark-green LCD ink.
final _pocketLcdTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF0F380F),
    secondary: Color(0xFF306230),
    surface: Color(0xFF8BAC0F),
  ),
  scaffoldBackgroundColor: const Color(0xFF9BBC0F),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFF9BBC0F),
  ),
  cardTheme: const CardThemeData(color: Color(0xFF8BAC0F)),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFF0F380F)),
    bodyMedium: TextStyle(color: Color(0xFF0F380F)),
    bodySmall: TextStyle(color: Color(0xFF306230)),
    titleLarge: TextStyle(color: Color(0xFF0F380F)),
    titleMedium: TextStyle(color: Color(0xFF0F380F)),
  ),
  iconTheme: const IconThemeData(color: Color(0xFF0F380F)),
  listTileTheme: const ListTileThemeData(
    textColor: Color(0xFF0F380F),
    iconColor: Color(0xFF306230),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF9BBC0F),
    foregroundColor: Color(0xFF0F380F),
    elevation: 0,
  ),
);

/// Concrete: bone paper, ink structure, signal-red accent.
final _concreteTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFFFF3D00),
    secondary: Color(0xFF16140F),
    tertiary: Color(0xFF16140F),
    surface: Color(0xFFFBFAF6),
  ),
  scaffoldBackgroundColor: const Color(0xFFE9E5DB),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFFE9E5DB),
  ),
  cardTheme: const CardThemeData(color: Color(0xFFFBFAF6)),
  dividerColor: const Color(0xFF16140F),
);

/// Sumi Ink: washi paper, sumi ink, vermillion seal accent.
final _sumiTheme = ThemeData.light().copyWith(
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: Color(0xFFC93A2E),
    secondary: Color(0xFF211E19),
    tertiary: Color(0xFF211E19),
    surface: Color(0xFFFBF8EE),
  ),
  scaffoldBackgroundColor: const Color(0xFFF5F1E4),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFFF5F1E4),
  ),
  cardTheme: const CardThemeData(color: Color(0xFFFBF8EE)),
);

/// Concrete Noir: charcoal slab, bone ink, signal red.
final _concreteNoirTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFFF3D00),
    secondary: Color(0xFFEDEAE2),
    tertiary: Color(0xFFEDEAE2),
    surface: Color(0xFF232327),
  ),
  scaffoldBackgroundColor: const Color(0xFF17171A),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFF17171A),
  ),
  cardTheme: const CardThemeData(color: Color(0xFF232327)),
  dividerColor: const Color(0xFFEDEAE2),
);

/// Sumi Night: charcoal paper, pale wash ink, live vermillion.
final _sumiNightTheme = ThemeData.dark().copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFC93A2E),
    secondary: Color(0xFFE8E2D2),
    tertiary: Color(0xFFE8E2D2),
    surface: Color(0xFF26251F),
  ),
  scaffoldBackgroundColor: const Color(0xFF1B1A16),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Color(0xFF1B1A16),
  ),
  cardTheme: const CardThemeData(color: Color(0xFF26251F)),
);
