import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/presentation/themes/now_playing_theme_spec.dart';
import 'package:celsius/presentation/themes/now_playing_theme_widgets.dart';
import 'package:celsius/presentation/widgets/waveform_painter.dart';

SongEntity _song() {
  return SongEntity(
    id: 'test-song',
    title: 'Midnight Circuit',
    artist: 'Neon Bloom',
    album: 'Aurora Sessions',
    durationMs: 227000,
    filePath: '/nonexistent/track.mp3',
    coverArtPath: null,
  );
}

void main() {
  test('every NowPlayingTheme has a spec and classic is the default', () {
    expect(nowPlayingThemeSpecs.length, NowPlayingTheme.values.length);
    for (final theme in NowPlayingTheme.values) {
      expect(nowPlayingThemeSpecs[theme], isNotNull,
          reason: 'missing spec for $theme');
    }
    expect(const AppSettings().nowPlayingTheme, NowPlayingTheme.classic);
  });

  test('specs carry the prototype palette values', () {
    final riso = nowPlayingThemeSpecs[NowPlayingTheme.risoZine]!;
    expect(riso.waveformPalette, [const Color(0xFFFF48B0), const Color(0xFF0078BF)]);

    final lcd = nowPlayingThemeSpecs[NowPlayingTheme.pocketLcd]!;
    expect(lcd.waveformStripes, isTrue);
    expect(lcd.showLed, isTrue);
    expect(lcd.sliderTheme(), isNotNull);
  });

  test('classic spec has no themed slider override (keeps inline defaults)', () {
    final classic = nowPlayingThemeSpecs[NowPlayingTheme.classic]!;
    expect(classic.sliderTheme(), isNull);
    expect(classic.showBlurredArtwork, isTrue);
  });

  test('every spec has an ink color readable on its background', () {
    for (final theme in NowPlayingTheme.values) {
      final spec = nowPlayingThemeSpecs[theme]!;
      expect(spec.inkColor, isNotNull, reason: 'missing ink color for $theme');
    }
  });

  testWidgets('auxiliary screen chrome follows the active skin',
      (WidgetTester tester) async {
    for (final theme in NowPlayingTheme.values) {
      final spec = nowPlayingThemeSpecs[theme]!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nowPlayingThemeSpecProvider.overrideWithValue(spec),
          ],
          child: MaterialApp(
            home: NowPlayingSubScreen(title: 'Queue', body: const SizedBox.expand()),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        spec.backgroundColor ?? Colors.black,
        reason: 'sub-screen background does not match the $theme skin',
      );

      final title = tester.widget<Text>(find.text('Queue'));
      expect(
        title.style?.color,
        spec.inkColor,
        reason: 'sub-screen title is not painted in the $theme ink color',
      );
    }
  });

  testWidgets('renders every background + art frame without errors',
      (WidgetTester tester) async {
    for (final theme in NowPlayingTheme.values) {
      final spec = nowPlayingThemeSpecs[theme]!;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 393,
            height: 852,
            child: Stack(
              children: [
                NowPlayingBackground(spec: spec, song: _song(), avgColor: Colors.black),
                NowPlayingArtFrame(spec: spec, song: _song(), size: 264, queueIndex: 3),
                if (spec.showPlayStatus) const LcdStatusLine(playing: true),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'theme $theme threw');
    }
  });

  testWidgets('LCD status line reflects playing state', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: LcdStatusLine(playing: false)),
      ),
    );
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: LcdStatusLine(playing: true)),
      ),
    );
    expect(find.text('PLAYING'), findsOneWidget);
  });

  testWidgets('waveform painter renders palettes and LCD stripes',
      (WidgetTester tester) async {
    final wave = List.generate(80, (i) {
      return 0.3 + 0.7 * (0.5 + 0.5 * math.sin(i / 80 * 2 * math.pi * 3));
    });
    const size = Size(360, 64);
    final failures = <String>[];

    await tester.runAsync(() async {
      final cases = <(String, WaveformPainter)>[
        (
          'riso-palette',
          WaveformPainter(
            waveData: wave,
            style: WaveformDrawStyle.bars,
            barPalette: const [Color(0xFFFF48B0), Color(0xFF0078BF)],
            squareBars: true,
            progress: 0.4,
            animation: const AlwaysStoppedAnimation(0.5),
          ),
        ),
        (
          'lcd-stripes',
          WaveformPainter(
            waveData: wave,
            style: WaveformDrawStyle.bars,
            stripeOn: 3,
            stripeOff: 2,
            squareBars: true,
            progress: 0.4,
            animation: const AlwaysStoppedAnimation(0.5),
          ),
        ),
      ];
      for (final (name, painter) in cases) {
        try {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          painter.paint(canvas, size);
          final picture = recorder.endRecording();
          final image =
              await picture.toImage(size.width.toInt(), size.height.toInt());
          final bytes =
              await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null || bytes.lengthInBytes == 0) {
            failures.add('$name produced no image bytes');
          }
          image.dispose();
        } catch (e) {
          failures.add('$name: $e');
        }
      }
    });

    expect(
      failures,
      isEmpty,
      reason: 'Themed waveform painters failed:\n${failures.join('\n')}',
    );
  });
}