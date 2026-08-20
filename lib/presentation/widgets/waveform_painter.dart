import 'dart:math';
import 'package:flutter/material.dart';

enum WaveformDrawStyle { bars, line, ribbon, wave, dots, equalizer, blocks, neon, radial }

class WaveformPainter extends CustomPainter {
  final List<double> waveData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final List<Color>? gradientColors;
  final WaveformDrawStyle style;
  final bool rainbow;
  final double barWidth;
  final double barSpacing;
  final double minHeight;
  final double maxHeight;
  final Animation<double>? animation;

  /// Per-bar color cycle (themed skins: Riso pink/blue, Swiss red accent).
  final List<Color>? barPalette;

  /// Square bar caps (themed skins) instead of round caps.
  final bool squareBars;

  /// Vertical ink stripe widths inside each bar (Pocket LCD).
  final double? stripeOn;
  final double? stripeOff;

  WaveformPainter({
    required this.waveData,
    this.progress = 0.0,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x40FFFFFF),
    this.gradientColors,
    this.style = WaveformDrawStyle.bars,
    this.rainbow = false,
    this.barWidth = 3.0,
    this.barSpacing = 2.0,
    this.minHeight = 3.0,
    this.maxHeight = 64.0,
    this.animation,
    this.barPalette,
    this.squareBars = false,
    this.stripeOn,
    this.stripeOff,
  }) : super(repaint: animation);

  /// Maximum amplitude modulation applied by the pulse animation.
  static const double _kPulseAmplitude = 0.15;

  /// Number of full wave cycles in the pulse animation per second.
  static const int _kPulseFreqCyclesPerTimeUnit = 2;

  /// Number of spatial wave cycles across the bar array for the pulse phase offset.
  static const int _kPulseSpatialCycles = 4;

  double _pulseFactor(int index, int barCount, double t) {
    if (t <= 0 || barCount <= 0) return 1.0;
    return 1.0 +
        _kPulseAmplitude *
            sin(2 * pi * t * _kPulseFreqCyclesPerTimeUnit +
                (index / barCount) * pi * _kPulseSpatialCycles);
  }

  Color _barColor(int index, int barCount, bool isActive, double amplitude) {
    final palette = barPalette;
    if (palette != null && palette.isNotEmpty) {
      final base = palette[index % palette.length];
      if (!isActive) return base.withValues(alpha: 0.22);
      return base.withValues(alpha: 0.6 + amplitude * 0.4);
    }
    if (rainbow) {
      final hue = (index / barCount) * 360;
      return HSVColor.fromAHSV(isActive ? 0.9 : 0.35, hue, 0.85, 1.0).toColor();
    }
    if (!isActive) return inactiveColor;
    final gradient = gradientColors;
    if (gradient == null || gradient.length < 2) {
      return activeColor.withValues(alpha: 0.5 + amplitude * 0.5);
    }
    final pos = barCount > 1 ? index / (barCount - 1) : 0.0;
    final scaled = pos * (gradient.length - 1);
    final i0 = scaled.floor().clamp(0, gradient.length - 1);
    final i1 = (i0 + 1).clamp(0, gradient.length - 1);
    final t = scaled - scaled.floor();
    return Color.lerp(gradient[i0], gradient[i1], t)!
        .withValues(alpha: 0.5 + amplitude * 0.5);
  }

  List<Color> _internalGradient() {
    final gradient = gradientColors;
    if (gradient == null || gradient.length < 2) {
      return [activeColor, activeColor];
    }
    return gradient;
  }

  List<Color> _rainbowColors(double alpha) {
    return List.generate(10, (i) {
      return HSVColor.fromAHSV(alpha, i * 40.0, 0.85, 1.0).toColor();
    });
  }

  int _barCount(Size size) {
    final maxFit = (size.width / (barWidth + barSpacing)).floor();
    return max(1, min(waveData.length, maxFit));
  }

  double _totalBarWidth(Size size, int barCount) {
    if (barCount <= 1) return 0;
    return (size.width - barWidth) / (barCount - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (waveData.isEmpty) return;

    switch (style) {
      case WaveformDrawStyle.bars:
        _paintBars(canvas, size);
        break;
      case WaveformDrawStyle.line:
        _paintLine(canvas, size);
        break;
      case WaveformDrawStyle.ribbon:
        _paintRibbon(canvas, size);
        break;
      case WaveformDrawStyle.wave:
        _paintWave(canvas, size);
        break;
      case WaveformDrawStyle.dots:
        _paintDots(canvas, size);
        break;
      case WaveformDrawStyle.equalizer:
        _paintEqualizer(canvas, size);
        break;
      case WaveformDrawStyle.blocks:
        _paintBlocks(canvas, size);
        break;
      case WaveformDrawStyle.neon:
        _paintNeon(canvas, size);
        break;
      case WaveformDrawStyle.radial:
        _paintRadial(canvas, size);
        break;
    }
  }

  void _paintBars(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = squareBars ? StrokeCap.butt : StrokeCap.round;
    final centerY = size.height / 2;
    final t = animation?.value ?? 0.0;

    final barCount = _barCount(size);
    final totalBarWidth = _totalBarWidth(size, barCount);

    for (int i = 0; i < barCount; i++) {
      final dataIndex = (i * waveData.length / barCount).floor();
      final amplitude = (waveData[dataIndex].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final barHeight = max(minHeight, size.height * amplitude * 0.8);
      final x = i * totalBarWidth + barWidth / 2;

      final barProgress = i / barCount;
      final isActive = barProgress <= progress;
      final barColor = _barColor(i, barCount, isActive, amplitude);

      final on = stripeOn;
      if (isActive && on != null && on > 0) {
        // Pocket LCD: fill each bar with a vertical ink-stripe shader.
        final off = stripeOff ?? on;
        final rect = Rect.fromLTWH(
          x - barWidth / 2,
          centerY - barHeight / 2,
          barWidth,
          barHeight,
        );
        canvas.drawRect(rect, Paint()..shader = _stripeShader(rect, barColor, on, off));
        continue;
      }

      paint
        ..strokeWidth = barWidth
        ..color = barColor;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  /// Vertical ink stripes: [on] px of color, [off] px transparent, repeating.
  static Shader _stripeShader(Rect rect, Color ink, double on, double off) {
    final colors = <Color>[];
    final stops = <double>[];
    double t = 0;
    while (t < 1.0 - 1e-6) {
      final onEnd = min(t + on / rect.height, 1.0);
      colors
        ..add(ink)
        ..add(ink)
        ..add(Colors.transparent)
        ..add(Colors.transparent);
      stops
        ..add(t)
        ..add(onEnd)
        ..add(onEnd)
        ..add(min(onEnd + off / rect.height, 1.0));
      if (onEnd >= 1.0) break;
      t = onEnd + off / rect.height;
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(rect);
  }

  void _paintRibbon(Canvas canvas, Size size) {
    final t = animation?.value ?? 0.0;
    final n = waveData.length;
    if (n < 2) return;

    final centerY = size.height / 2;
    double amplitudeAt(int i) =>
        (waveData[i].clamp(0.05, 1.0) * _pulseFactor(i, n, t)).clamp(0.0, 1.0);
    double xAt(int i) => (i / (n - 1)) * size.width;
    double yAt(int i) => centerY - size.height * amplitudeAt(i) * 0.42;

    // Ribbon: top edge forward, mirrored bottom edge back - a symmetric
    // filled band that reads like a tape across the screen.
    final ribbon = Path();
    for (int i = 0; i < n; i++) {
      if (i == 0) {
        ribbon.moveTo(xAt(i), yAt(i));
      } else {
        ribbon.lineTo(xAt(i), yAt(i));
      }
    }
    for (int i = n - 1; i >= 0; i--) {
      ribbon.lineTo(xAt(i), centerY + (centerY - yAt(i)));
    }
    ribbon.close();

    final progressX = progress * size.width;

    final fill = Paint()..style = PaintingStyle.fill;

    // Unplayed portion.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(progressX, 0, size.width, size.height));
    if (rainbow) {
      fill.shader = LinearGradient(colors: _rainbowColors(0.3)).createShader(Offset.zero & size);
    } else {
      fill.shader = null;
      fill.color = inactiveColor.withValues(alpha: 0.22);
    }
    canvas.drawPath(ribbon, fill);
    canvas.restore();

    // Played portion.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, progressX, size.height));
    if (rainbow) {
      fill.shader = LinearGradient(colors: _rainbowColors(1.0)).createShader(Offset.zero & size);
    } else if (gradientColors != null) {
      fill.shader = LinearGradient(colors: _internalGradient()).createShader(Offset.zero & size);
    } else {
      fill.shader = null;
      fill.color = activeColor;
    }
    canvas.drawPath(ribbon, fill);
    canvas.restore();

    // Subtle center spine keeps the ribbon anchored.
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 1,
    );
  }

  void _paintNeon(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final centerY = size.height / 2;
    final t = animation?.value ?? 0.0;

    final barCount = _barCount(size);
    final totalBarWidth = _totalBarWidth(size, barCount);
    final glowPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth + 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    for (int i = 0; i < barCount; i++) {
      final dataIndex = (i * waveData.length / barCount).floor();
      final amplitude = (waveData[dataIndex].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final barHeight = max(minHeight, size.height * amplitude * 0.8);
      final x = i * totalBarWidth + barWidth / 2;

      final barProgress = i / barCount;
      final isActive = barProgress <= progress;
      final barColor = _barColor(i, barCount, isActive, amplitude);

      if (isActive) {
        glowPaint.color = barColor.withValues(alpha: 0.45);
        canvas.drawLine(
          Offset(x, centerY - barHeight / 2),
          Offset(x, centerY + barHeight / 2),
          glowPaint,
        );
      }

      paint
        ..strokeWidth = barWidth
        ..color = barColor;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  void _paintEqualizer(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final bottom = size.height;
    final t = animation?.value ?? 0.0;

    final barCount = _barCount(size);
    final totalBarWidth = _totalBarWidth(size, barCount);

    for (int i = 0; i < barCount; i++) {
      final dataIndex = (i * waveData.length / barCount).floor();
      final amplitude = (waveData[dataIndex].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final barHeight = max(minHeight, size.height * amplitude * 0.9);
      final x = i * totalBarWidth;

      final barProgress = i / barCount;
      final isActive = barProgress <= progress;
      paint.color = _barColor(i, barCount, isActive, amplitude);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, bottom - barHeight, x + barWidth, bottom),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  void _paintDots(Canvas canvas, Size size) {
    final paint = Paint();
    final centerY = size.height / 2;
    final t = animation?.value ?? 0.0;

    final barCount = _barCount(size);
    final totalBarWidth = _totalBarWidth(size, barCount);
    final maxRadius = min(size.height, totalBarWidth) * 0.32;

    for (int i = 0; i < barCount; i++) {
      final dataIndex = (i * waveData.length / barCount).floor();
      final amplitude = (waveData[dataIndex].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final radius = max(1.0, maxRadius * amplitude);
      final x = i * totalBarWidth + barWidth / 2;

      final barProgress = i / barCount;
      final isActive = barProgress <= progress;
      paint.color = _barColor(i, barCount, isActive, amplitude);

      canvas.drawCircle(Offset(x, centerY), radius, paint);
    }
  }

  void _paintBlocks(Canvas canvas, Size size) {
    final paint = Paint();
    final centerY = size.height / 2;
    final t = animation?.value ?? 0.0;

    final barCount = _barCount(size);
    final totalBarWidth = _totalBarWidth(size, barCount);
    const blockCount = 6;
    final blockHeight = size.height * 0.72 / blockCount;

    for (int i = 0; i < barCount; i++) {
      final dataIndex = (i * waveData.length / barCount).floor();
      final amplitude = (waveData[dataIndex].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final litBlocks = max(1, (amplitude * blockCount).ceil());
      final x = i * totalBarWidth;

      final barProgress = i / barCount;
      final isActive = barProgress <= progress;

      for (int k = 1; k <= litBlocks; k++) {
        final brightness = k / blockCount;
        paint.color = _ledColor(i, barCount, isActive, brightness);

        final top = centerY - blockHeight * k;
        final bottom = centerY - blockHeight * (k - 1);
        final mirrorTop = centerY + blockHeight * (k - 1);
        final mirrorBottom = centerY + blockHeight * k;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTRB(x, top, x + barWidth, bottom),
          const Radius.circular(1.5),
        );
        final rrectMirror = RRect.fromRectAndRadius(
          Rect.fromLTRB(x, mirrorTop, x + barWidth, mirrorBottom),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rrect, paint);
        canvas.drawRRect(rrectMirror, paint);
      }
    }
  }

  Color _ledColor(int index, int barCount, bool isActive, double brightness) {
    if (rainbow) {
      final hue = (index / barCount) * 360;
      final base = isActive ? 0.9 : 0.3;
      return HSVColor.fromAHSV(base * (0.4 + 0.6 * brightness), hue, 0.85, 1.0).toColor();
    }
    final ref = isActive ? activeColor : inactiveColor;
    final alpha = (isActive ? 0.35 : 0.2) + (isActive ? 0.65 : 0.35) * brightness;
    return ref.withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  void _paintLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final inactivePath = Path();
    final centerY = size.height / 2;
    final t = animation?.value ?? 0.0;
    final barCount = waveData.length;

    for (int i = 0; i < waveData.length; i++) {
      final x = (i / (waveData.length - 1)) * size.width;
      final amplitude = (waveData[i].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final y = centerY - (size.height * amplitude * 0.4);

      if (i == 0) {
        path.moveTo(x, y);
        inactivePath.moveTo(x, y);
      } else {
        final prevX = ((i - 1) / (waveData.length - 1)) * size.width;
        final prevAmp = waveData[i - 1].clamp(0.05, 1.0);
        final prevY = centerY - (size.height * prevAmp * 0.4);
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
        inactivePath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }

    final progressX = progress * size.width;
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final activePath = metrics.first.extractPath(0, progressX);

    if (rainbow) {
      paint.shader = LinearGradient(colors: _rainbowColors(0.35)).createShader(Offset.zero & size);
      canvas.drawPath(inactivePath, paint);
      paint.shader = LinearGradient(colors: _rainbowColors(1.0)).createShader(Offset.zero & size);
      canvas.drawPath(activePath, paint);
      return;
    }

    if (gradientColors != null) {
      paint.shader =
          LinearGradient(colors: _internalGradient()).createShader(Offset.zero & size);
      canvas.drawPath(activePath, paint);
      return;
    }

    paint.shader = null;
    paint.color = inactiveColor;
    canvas.drawPath(inactivePath, paint);

    paint.color = activeColor;
    canvas.drawPath(activePath, paint);
  }

  void _paintWave(Canvas canvas, Size size) {
    final t = animation?.value ?? 0.0;
    final n = waveData.length;
    if (n < 2) return;

    final path = Path();
    for (int i = 0; i < n; i++) {
      final x = (i / (n - 1)) * size.width;
      final amplitude = (waveData[i].clamp(0.05, 1.0) * _pulseFactor(i, n, t)).clamp(0.0, 1.0);
      final y = size.height / 2 - (size.height * amplitude * 0.42);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final filled = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final progressX = progress * size.width;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(progressX, 0, size.width, size.height));
    if (rainbow) {
      fill.shader = null;
      fill.shader = LinearGradient(colors: _rainbowColors(0.4)).createShader(Offset.zero & size);
      stroke.shader = LinearGradient(colors: _rainbowColors(0.4)).createShader(Offset.zero & size);
    } else if (gradientColors != null) {
      fill.shader = null;
      fill.shader = LinearGradient(colors: _internalGradient())
          .createShader(Offset.zero & size);
      stroke.shader = null;
      stroke.color = inactiveColor;
    } else {
      fill.shader = null;
      fill.color = inactiveColor.withValues(alpha: 0.35);
      stroke.color = inactiveColor;
    }
    canvas.drawPath(filled, fill);
    canvas.drawPath(path, stroke);
    canvas.restore();

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, progressX, size.height));
    if (rainbow) {
      fill.shader = null;
      fill.shader = LinearGradient(colors: _rainbowColors(1.0)).createShader(Offset.zero & size);
      stroke.shader = LinearGradient(colors: _rainbowColors(1.0)).createShader(Offset.zero & size);
    } else if (gradientColors != null) {
      fill.shader = null;
      fill.shader = LinearGradient(colors: _internalGradient())
          .createShader(Offset.zero & size);
      stroke.shader = null;
      stroke.color = activeColor;
    } else {
      fill.shader = null;
      fill.color = activeColor;
      stroke.color = activeColor;
    }
    canvas.drawPath(filled, fill);
    canvas.drawPath(path, stroke);
    canvas.restore();
  }

  void _paintRadial(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.32;
    final maxBarHeight = min(size.width, size.height) * 0.15;
    final barCount = min(waveData.length, 60);
    final t = animation?.value ?? 0.0;

    for (int i = 0; i < barCount; i++) {
      final angle = (i / barCount) * 2 * pi - pi / 2;
      final dataIndex = (i * waveData.length / barCount).floor();
      final amplitude = (waveData[dataIndex].clamp(0.05, 1.0) * _pulseFactor(i, barCount, t)).clamp(0.0, 1.0);
      final barHeight = max(2.0, maxBarHeight * amplitude);

      final innerPoint = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );
      final outerPoint = Offset(
        center.dx + cos(angle) * (radius + barHeight),
        center.dy + sin(angle) * (radius + barHeight),
      );

      final barProgress = i / barCount;
      final isActive = barProgress <= progress;
      final barColor = _barColor(i, barCount, isActive, amplitude);

      paint
        ..strokeWidth = max(1.5, (2 * pi * radius / barCount) * 0.35)
        ..color = barColor;

      canvas.drawLine(innerPoint, outerPoint, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.gradientColors != gradientColors ||
        oldDelegate.rainbow != rainbow ||
        oldDelegate.style != style ||
        oldDelegate.waveData != waveData ||
        oldDelegate.barPalette != barPalette ||
        oldDelegate.squareBars != squareBars ||
        oldDelegate.stripeOn != stripeOn ||
        oldDelegate.stripeOff != stripeOff;
  }
}