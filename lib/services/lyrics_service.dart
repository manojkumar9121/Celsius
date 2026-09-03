import 'dart:collection';

import 'package:flutter_audio_tagger/flutter_audio_tagger.dart';

/// Maximum number of entries to keep in the lyrics cache before evicting the oldest.
const int _kMaxLyricsCacheEntries = 100;

class LyricsService {
  static final LyricsService _instance = LyricsService._();
  factory LyricsService() => _instance;
  LyricsService._();

  final FlutterAudioTagger _tagger = FlutterAudioTagger();
  /// LinkedHashMap with insertion ordering. Accessing a key (remove + re-insert)
  /// promotes it to the end so it becomes the most recently used. Eviction
  /// removes from the front (oldest entry) until under [_kMaxLyricsCacheEntries].
  final LinkedHashMap<String, String?> _cache = LinkedHashMap<String, String?>();

  Future<String?> getLyrics(String filePath) async {
    if (_cache.containsKey(filePath)) {
      // Remove and re-insert to promote to "most recently used".
      final value = _cache[filePath];
      _cache.remove(filePath);
      _cache[filePath] = value;
      return value;
    }

    try {
      final tag = await _tagger.getAllTags(filePath);
      final lyrics = tag?.lyrics;
      _cache[filePath] = lyrics;
      _evictIfNeeded();
      return lyrics;
    } catch (_) {
      _cache[filePath] = null;
      _evictIfNeeded();
      return null;
    }
  }

  /// Removes the oldest cache entries until we're back under the limit.
  void _evictIfNeeded() {
    while (_cache.length > _kMaxLyricsCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  List<LyricLine> parseLrc(String lrcContent) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{0,3})\](.*)');

    for (final line in lrcContent.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msStr = match.group(3) ?? '0';
        final ms = msStr.isNotEmpty ? int.parse(msStr.padRight(3, '0')) : 0;
        final text = match.group(4)?.trim() ?? '';

        if (text.isNotEmpty) {
          final timeMs = (minutes * 60 + seconds) * 1000 + ms;
          lines.add(LyricLine(timeMs: timeMs, text: text));
        }
      }
    }

    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  int getCurrentLineIndex(List<LyricLine> lyrics, Duration position) {
    final posMs = position.inMilliseconds;
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (posMs >= lyrics[i].timeMs) return i;
    }
    return 0;
  }

  void clearCache() {
    _cache.clear();
  }
}

class LyricLine {
  final int timeMs;
  final String text;

  const LyricLine({required this.timeMs, required this.text});
}
