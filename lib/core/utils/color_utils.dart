import 'dart:typed_data';
import 'package:flutter/material.dart';

Color parseHexColor(String hex) {
  try {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    } else if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    debugPrint('parseHexColor: unsupported hex format "$hex"');
  } catch (e) {
    debugPrint('parseHexColor: invalid hex "$hex": $e');
  }
  return Colors.grey;
}

/// Derives a single "themeable" color from raw RGBA pixels (e.g. a downscaled
/// album art decode).
///
/// Plain black, white or grayscale covers carry no meaningful hue - they fall
/// back to [fallback] (the app's primary color) instead of producing a muddy or
/// invisible accent that breaks the now-playing screen. When the artwork has
/// color, the most vibrant pixels are preferred (Palette API style) over a
/// plain average, and the result is normalized into a readable mid-tone.
Color dominantColorFromRgba(Uint8List rgba, Color fallback) {
  int r = 0, g = 0, b = 0, count = 0;
  int vr = 0, vg = 0, vb = 0, vCount = 0;
  double satSum = 0;

  for (int i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 40) continue;
    final cr = rgba[i], cg = rgba[i + 1], cb = rgba[i + 2];
    final hsl = HSLColor.fromColor(Color.fromARGB(255, cr, cg, cb));
    r += cr;
    g += cg;
    b += cb;
    count++;
    satSum += hsl.saturation;
    if (hsl.saturation > 0.28 && hsl.lightness > 0.15 && hsl.lightness < 0.88) {
      vr += cr;
      vg += cg;
      vb += cb;
      vCount++;
    }
  }
  if (count == 0) return fallback;

  final avg = Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
  final avgSat = satSum / count;
  final avgLight = HSLColor.fromColor(avg).lightness;
  if (avgSat < 0.12 || avgLight < 0.10 || avgLight > 0.92) {
    return fallback;
  }

  // Prefer the most vibrant pixels when enough exist.
  final useVibrant = vCount > count ~/ 8;
  final base = HSLColor.fromColor(Color.fromARGB(
    255,
    useVibrant ? vr ~/ vCount : r ~/ count,
    useVibrant ? vg ~/ vCount : g ~/ count,
    useVibrant ? vb ~/ vCount : b ~/ count,
  ));

  return HSLColor.fromAHSL(
    1,
    base.hue,
    (base.saturation * 1.15).clamp(0.35, 1.0),
    base.lightness.clamp(0.35, 0.65),
  ).toColor();
}
