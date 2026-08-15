import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class WaveformExtractorService {
  static WaveformExtractorService? _instance;
  static WaveformExtractorService get instance => _instance ??= WaveformExtractorService._();
  WaveformExtractorService._();

  static const _boxName = 'waveform_cache';
  static const _maxBars = 80;

  Box<String>? _cacheBox;

  Future<void> init() async {
    _cacheBox = await Hive.openBox<String>(_boxName);
  }

  Future<List<double>> extractWaveform(String audioPath, {int? barCount}) async {
    final cacheKey = audioPath;

    final cached = _cacheBox?.get(cacheKey);
    if (cached != null) {
      return cached.split(',').map(double.parse).toList();
    }

    final data = await compute(_extractWaveformIsolate, audioPath);

    if (data.isNotEmpty) {
      final downscaled = _downscale(data, barCount ?? _maxBars);
      await _cacheBox?.put(cacheKey, downscaled.map((e) => e.toStringAsFixed(4)).join(','));
      return downscaled;
    }

    return _generateFallbackBars(barCount ?? _maxBars);
  }

  List<double> _downscale(List<double> original, int targetSize) {
    if (original.isEmpty) return _generateFallbackBars(targetSize);
    if (original.length <= targetSize) return original;

    final result = <double>[];
    final chunkSize = original.length / targetSize;

    for (int i = 0; i < targetSize; i++) {
      final start = (i * chunkSize).floor();
      final end = ((i + 1) * chunkSize).floor().clamp(0, original.length);
      double maxVal = 0;
      for (int j = start; j < end; j++) {
        if (original[j] > maxVal) maxVal = original[j];
      }
      result.add(maxVal.clamp(0.0, 1.0));
    }

    return result;
  }

  List<double> _generateFallbackBars(int count) {
    final random = Random(42);
    return List.generate(count, (_) => random.nextDouble() * 0.3 + 0.1);
  }

  static List<double> _extractWaveformIsolate(String audioPath) {
    try {
      final file = File(audioPath);
      if (!file.existsSync()) return [];

      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return [];

      final samples = <double>[];
      final sampleCount = 2000;
      final chunkSize = bytes.length ~/ sampleCount;

      for (int i = 0; i < sampleCount && i * chunkSize < bytes.length; i++) {
        final start = i * chunkSize;
        final end = min(start + chunkSize, bytes.length);

        double sum = 0;
        int count = 0;
        for (int j = start; j < end - 1; j += 2) {
          final sample = (bytes[j] | (bytes[j + 1] << 8)) / 32768.0;
          sum += sample.abs();
          count++;
        }
        samples.add(count > 0 ? sum / count : 0);
      }

      if (samples.isEmpty) return [];

      final maxSample = samples.reduce(max);
      if (maxSample == 0) return samples.map((_) => 0.05).toList();

      return samples.map((s) => (s / maxSample).clamp(0.0, 1.0)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Removes the cached waveform for [audioPath], if any. Used when a song
  /// is deleted from the library so stale entries don't accumulate.
  Future<void> removeFromCache(String audioPath) async {
    try {
      final box = _cacheBox ?? await Hive.openBox<String>(_boxName);
      await box.delete(audioPath);
    } catch (e) {
      debugPrint('Failed to clear waveform cache for $audioPath: $e');
    }
  }

  void dispose() {
    _cacheBox?.close();
  }
}
