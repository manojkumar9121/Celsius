import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:celsius/core/utils/color_utils.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/presentation/providers/settings_provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('celsius_settings_test');
    Hive.init(tempDir.path);
    await HiveStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('settings persistence', () {
    test('now playing theme survives a "restart" (re-read from storage)', () {
      final notifier = SettingsNotifier();
      notifier.setNowPlayingTheme(NowPlayingTheme.pocketLcd);
      final reloaded = SettingsNotifier().state;
      expect(reloaded.nowPlayingTheme, NowPlayingTheme.pocketLcd);
    });

    test('custom color survives a "restart" (re-read from storage)', () {
      final notifier = SettingsNotifier();
      notifier.setThemePreset(ThemePreset.nord);

      final restored = HiveStorage.getSettings();
      expect(restored.themePreset, ThemePreset.nord);
    });

    test('primary color + custom preset survive a restart', () {
      final notifier = SettingsNotifier();
      notifier.setPrimaryColor(const Color(0xFF1976D2));

      final restored = HiveStorage.getSettings();
      expect(restored.themePreset, ThemePreset.custom);
      expect(restored.primaryColor, '#1976d2');
    });

    test('custom preset maps to dark mode so the chosen color is always visible',
        () {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier()
            ..setPrimaryColor(const Color(0xFF1976D2)),
        ),
      ]);
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('matching presets auto-switch the Now Playing skin', () {
      final notifier = SettingsNotifier();
      notifier.setThemePreset(ThemePreset.risoZine);
      expect(notifier.state.nowPlayingTheme, NowPlayingTheme.risoZine);

      notifier.setThemePreset(ThemePreset.paperPress);
      expect(notifier.state.nowPlayingTheme, NowPlayingTheme.paperPress);

      notifier.setThemePreset(ThemePreset.pocketLcd);
      expect(notifier.state.nowPlayingTheme, NowPlayingTheme.pocketLcd);

      // Non-matching presets leave the skin untouched.
      notifier.setNowPlayingTheme(NowPlayingTheme.classic);
      notifier.setThemePreset(ThemePreset.nord);
      expect(notifier.state.nowPlayingTheme, NowPlayingTheme.classic);
    });

    test('matching presets map to light mode (cream/olive backgrounds)', () {
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier()..setThemePreset(ThemePreset.paperPress),
        ),
      ]);
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.light);
    });
  });

  group('dominantColorFromRgba', () {
    final fallback = const Color(0xFF1976D2);

    Uint8List solid(int r, int g, int b, {int n = 32 * 32}) {
      final data = Uint8List(n * 4);
      for (int i = 0; i < n; i++) {
        data[i * 4] = r;
        data[i * 4 + 1] = g;
        data[i * 4 + 2] = b;
        data[i * 4 + 3] = 255;
      }
      return data;
    }

    test('white artwork falls back to theme color', () {
      final result = dominantColorFromRgba(solid(255, 255, 255), fallback);
      expect(result, fallback);
    });

    test('black artwork falls back to theme color', () {
      final result = dominantColorFromRgba(solid(0, 0, 0), fallback);
      expect(result, fallback);
    });

    test('gray artwork falls back to theme color', () {
      final result = dominantColorFromRgba(solid(128, 128, 128), fallback);
      expect(result, fallback);
    });

    test('solid red artwork yields a saturated red accent', () {
      final result = dominantColorFromRgba(solid(220, 30, 30), fallback);
      final hsl = HSLColor.fromColor(result);
      expect(hsl.hue, closeTo(0, 25));
      expect(hsl.saturation, greaterThan(0.5));
    });

    test('vibrant pixels preferred over a muddy average', () {
      // Mostly gray, with a saturated red pocket large enough to drive the
      // overall saturation above the colorless threshold.
      final data = solid(128, 128, 128);
      for (int i = 0; i < 160; i++) {
        data[i * 4] = 230;
        data[i * 4 + 1] = 20;
        data[i * 4 + 2] = 20;
      }
      final result = dominantColorFromRgba(data, fallback);
      final hsl = HSLColor.fromColor(result);
      expect(hsl.hue, closeTo(0, 30));
      expect(hsl.saturation, greaterThan(0.5));
    });
  });
}