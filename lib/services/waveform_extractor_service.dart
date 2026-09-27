import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class _WaveformCacheEntry {
  final int sequence;
  final List<double> bars;

  const _WaveformCacheEntry({required this.sequence, required this.bars});
}

class WaveformExtractorService {
  static WaveformExtractorService? _instance;
  static WaveformExtractorService get instance =>
      _instance ??= WaveformExtractorService._();
  WaveformExtractorService._();

  static const _boxName = 'waveform_cache';
  static const _maxBars = 80;

  /// Upper bound for persisted waveform entries. The in-memory LRU only caps
  /// RAM; without this the disk box grows without bound on rescans/renames.
  static const _maxDiskEntries = 500;
  static const _entryPrefix = 'v1:';

  Box<String>? _cacheBox;
  int _nextAccessSequence = 0;
  int _cacheEpoch = 0;
  Future<void> _cacheMutationQueue = Future<void>.value();

  Future<void> init() async {
    _cacheBox = await Hive.openBox<String>(_boxName);
    _seedNextAccessSequence(_cacheBox!);
    try {
      await _enforceDiskCap();
    } catch (error) {
      debugPrint('Failed to enforce waveform disk cap during init: $error');
    }
  }

  Future<List<double>> extractWaveform(
    String audioPath, {
    int? barCount,
  }) async {
    final cacheKey = audioPath;
    final extractionEpoch = _cacheEpoch;
    final box = _cacheBox;
    final cached = box?.get(cacheKey);
    if (cached != null) {
      final entry = _decodeEntry(cached);
      if (entry != null) {
        try {
          await _touch(cacheKey, entry.bars, extractionEpoch);
        } catch (error) {
          // Recency bookkeeping must never invalidate an otherwise usable hit.
          debugPrint('Failed to touch waveform cache for $cacheKey: $error');
        }
        return entry.bars;
      }
      // Poison entry (bit-flip, partial write): evict so this song heals on
      // re-extract instead of throwing on every Now Playing visit.
      try {
        await _mutateCache(() => box!.delete(cacheKey));
      } catch (error) {
        debugPrint(
          'Failed to evict corrupt waveform cache for $cacheKey: $error',
        );
      }
    }

    final data = await compute(_extractWaveformIsolate, audioPath);
    if (data.isNotEmpty) {
      final downscaled = _downscale(data, barCount ?? _maxBars);
      try {
        await _store(cacheKey, downscaled, extractionEpoch);
      } catch (error) {
        debugPrint('Failed to store waveform cache for $cacheKey: $error');
      }
      return downscaled;
    }

    return _generateFallbackBars(barCount ?? _maxBars);
  }

  /// Parses a cached payload, or null when it is corrupt (never throws —
  /// corrupt data is the service's problem, not the caller's).
  List<double>? _parseCached(String cached) {
    try {
      final parsed = cached.split(',').map(double.parse).toList();
      if (parsed.isEmpty) return null;
      if (parsed.any((v) => v.isNaN || v.isInfinite)) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  _WaveformCacheEntry? _decodeEntry(String raw) {
    var sequence = 0;
    var payload = raw;
    if (raw.startsWith(_entryPrefix)) {
      final separator = raw.indexOf(':', _entryPrefix.length);
      if (separator < 0) return null;
      final parsedSequence = int.tryParse(
        raw.substring(_entryPrefix.length, separator),
      );
      if (parsedSequence == null || parsedSequence < 0) return null;
      sequence = parsedSequence;
      payload = raw.substring(separator + 1);
    }
    final bars = _parseCached(payload);
    if (bars == null) return null;
    return _WaveformCacheEntry(sequence: sequence, bars: bars);
  }

  String _encodeEntry(int sequence, List<double> bars) {
    return '$_entryPrefix$sequence:${bars.map((e) => e.toStringAsFixed(4)).join(',')}';
  }

  void _seedNextAccessSequence(Box<String> box) {
    var maximum = 0;
    for (final raw in box.values) {
      final entry = _decodeEntry(raw);
      if (entry != null && entry.sequence > maximum) maximum = entry.sequence;
    }
    _nextAccessSequence = maximum;
  }

  Future<void> _mutateCache(Future<void> Function() operation) {
    final next = _cacheMutationQueue.then((_) => operation());
    _cacheMutationQueue = next.catchError((Object error) {
      debugPrint('Waveform cache mutation failed: $error');
    });
    return next;
  }

  Future<void> _touch(String key, List<double> bars, int extractionEpoch) {
    return _mutateCache(() async {
      if (extractionEpoch != _cacheEpoch) return;
      final box = _cacheBox;
      if (box == null) return;
      final sequence = ++_nextAccessSequence;
      await box.put(key, _encodeEntry(sequence, bars));
    });
  }

  Future<void> _store(String key, List<double> bars, int extractionEpoch) {
    return _mutateCache(() async {
      if (extractionEpoch != _cacheEpoch) return;
      final box = _cacheBox;
      if (box == null) return;
      final sequence = ++_nextAccessSequence;
      await box.put(key, _encodeEntry(sequence, bars));
      await _enforceDiskCapUnqueued(box);
    });
  }

  Future<void> _enforceDiskCap() {
    return _mutateCache(() async {
      final box = _cacheBox;
      if (box != null) await _enforceDiskCapUnqueued(box);
    });
  }

  /// Evicts least-recently-used entries using the persisted access sequence.
  /// Legacy CSV records have sequence zero; their path is a deterministic
  /// tie-breaker because their original recency is unknowable.
  Future<void> _enforceDiskCapUnqueued(Box<String> box) async {
    var validCount = 0;
    final invalidKeys = <String>[];
    for (final key in box.keys.toList()) {
      if (_decodeEntry(box.get(key) ?? '') == null) {
        invalidKeys.add(key);
      } else {
        validCount++;
      }
    }
    if (invalidKeys.isNotEmpty) await box.deleteAll(invalidKeys);
    if (validCount <= _maxDiskEntries) return;

    final keyedEntries = <MapEntry<String, _WaveformCacheEntry>>[];
    for (final key in box.keys.toList()) {
      final entry = _decodeEntry(box.get(key) ?? '');
      if (entry != null) {
        keyedEntries.add(MapEntry(key, entry));
      }
    }
    keyedEntries.sort((a, b) {
      final bySequence = a.value.sequence.compareTo(b.value.sequence);
      return bySequence != 0 ? bySequence : a.key.compareTo(b.key);
    });
    final overflow = keyedEntries.length - _maxDiskEntries;
    if (overflow > 0) {
      await box.deleteAll([
        for (var i = 0; i < overflow; i++) keyedEntries[i].key,
      ]);
    }
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
    _cacheEpoch++;
    try {
      var box = _cacheBox;
      if (box == null || !box.isOpen) {
        box = await Hive.openBox<String>(_boxName);
        _cacheBox = box;
      }
      await _mutateCache(() => box!.delete(audioPath));
    } catch (e) {
      debugPrint('Failed to clear waveform cache for $audioPath: $e');
    }
  }

  /// Drops the entire disk cache. Used when the library is cleared, at
  /// which point every entry is orphaned; entries rebuild lazily.
  Future<void> clearCache() async {
    _cacheEpoch++;
    try {
      var box = _cacheBox;
      if (box == null || !box.isOpen) {
        box = await Hive.openBox<String>(_boxName);
        _cacheBox = box;
      }
      await _mutateCache(() => box!.clear());
    } catch (e) {
      debugPrint('Failed to clear waveform cache: $e');
    }
  }

  void dispose() {
    _cacheBox?.close();
  }
}
