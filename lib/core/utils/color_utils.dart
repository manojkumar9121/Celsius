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
/// Uses color quantization: similar colors are grouped into bins, the most
/// frequent non-neutral bin is selected, and the result is normalized into a
/// readable mid-tone suitable for waveform / accent use.
///
/// Plain black, white or grayscale covers carry no meaningful hue and fall
/// back to [fallback] (the app's primary color).
Color dominantColorFromRgba(Uint8List rgba, Color fallback) {
  const int binShift = 3; // 8 levels per channel → 512 bins

  // binKey → [sumR, sumG, sumB, count]
  final Map<int, List<int>> bins = {};
  int totalPixels = 0;

  for (int i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 40) continue;
    final cr = rgba[i], cg = rgba[i + 1], cb = rgba[i + 2];

    // Skip near-black and near-white pixels — they're usually background
    // or paper and rarely the intended accent color.
    final maxc = cr > cg ? (cr > cb ? cr : cb) : (cg > cb ? cg : cb);
    final minc = cr < cg ? (cr < cb ? cr : cb) : (cg < cb ? cg : cb);
    if (maxc < 30 || minc > 225) continue;

    final key = ((cr >> binShift) << 16) | ((cg >> binShift) << 8) | (cb >> binShift);
    final bin = bins[key];
    if (bin != null) {
      bin[0] += cr;
      bin[1] += cg;
      bin[2] += cb;
      bin[3]++;
    } else {
      bins[key] = [cr, cg, cb, 1];
    }
    totalPixels++;
  }

  if (totalPixels == 0 || bins.isEmpty) return fallback;

  // Find the bin with the most pixels (the dominant color cluster).
  List<int>? bestBin;
  int bestCount = 0;
  for (final bin in bins.values) {
    if (bin[3] > bestCount) {
      bestCount = bin[3];
      bestBin = bin;
    }
  }
  if (bestBin == null || bestCount < totalPixels ~/ 32) return fallback;

  // Collect all bins sorted by count descending so we can fall back to the
  // next-most-populous non-neutral bin when the dominant one is gray.
  final sortedBins = bins.values.toList()..sort((a, b) => b[3].compareTo(a[3]));

  for (final bin in sortedBins) {
    final avgR = bin[0] ~/ bin[3];
    final avgG = bin[1] ~/ bin[3];
    final avgB = bin[2] ~/ bin[3];
    final base = HSLColor.fromColor(Color.fromARGB(255, avgR, avgG, avgB));

    if (base.saturation >= 0.08) {
      // Normalize into a readable mid-tone for waveform / accent use.
      return HSLColor.fromAHSL(
        1,
        base.hue,
        base.saturation.clamp(0.30, 1.0),
        base.lightness.clamp(0.35, 0.65),
      ).toColor();
    }
  }

  return fallback;
}
