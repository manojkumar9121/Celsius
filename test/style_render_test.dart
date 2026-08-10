import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsuis/presentation/widgets/waveform_painter.dart';

void main() {
  testWidgets('render all waveform styles to png', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final wave = List.generate(80, (i) {
        return 0.3 + 0.7 * (0.5 + 0.5 * math.sin(i / 80 * 2 * math.pi * 3));
      });
      const size = Size(360, 64);

      // Minimal PathMetrics probe
      final probe = Path()
        ..moveTo(0, 10)
        ..cubicTo(10, 5, 20, 15, 30, 10);
      final pm = probe.computeMetrics();
      debugPrint('probe isEmpty=${pm.isEmpty} first=${pm.isEmpty ? "n/a" : pm.first}');

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
            File('/tmp/wave_${style.name}${r ? '' : '_solid'}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          } catch (e) {
            debugPrint('FAIL ${style.name} rainbow=$r: $e');
          }
        }
      }
    });
  });
}