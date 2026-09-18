import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsius/presentation/widgets/waveform_painter.dart';

void main() {
  testWidgets('renders all waveform styles without errors', (WidgetTester tester) async {
    final failures = <String>[];
    await tester.runAsync(() async {
      final wave = List.generate(80, (i) {
        return 0.3 + 0.7 * (0.5 + 0.5 * math.sin(i / 80 * 2 * math.pi * 3));
      });
      const size = Size(360, 64);

      for (final style in WaveformDrawStyle.values) {
        for (final r in [true, false]) {
          try {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            final painter = WaveformPainter(
              waveData: wave,
              style: style,
              rainbow: r,
              activeColor: Colors.greenAccent,
              inactiveColor: Colors.white24,
              progress: 0.4,
              animation: const AlwaysStoppedAnimation(0.5),
            );
            painter.paint(canvas, size);
            final picture = recorder.endRecording();
            final image =
                await picture.toImage(size.width.toInt(), size.height.toInt());
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            if (bytes == null || bytes.lengthInBytes == 0) {
              failures.add('${style.name} rainbow=$r produced no image bytes');
            }
            image.dispose();
          } catch (e) {
            failures.add('${style.name} rainbow=$r: $e');
          }
        }
      }
    });

    expect(
      failures,
      isEmpty,
      reason: 'Waveform styles failed to render:\n${failures.join('\n')}',
    );
  });
}