import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

class WidgetService {
  static final WidgetService _instance = WidgetService._();
  factory WidgetService() => _instance;
  WidgetService._();

  static const _channel = MethodChannel('com.celsuis.celsuis/widget');
  bool _initialized = false;

  Function()? onPrevious;
  Function()? onPlayPause;
  Function()? onNext;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ACTION_PREV':
          onPrevious?.call();
          break;
        case 'ACTION_PLAY_PAUSE':
          onPlayPause?.call();
          break;
        case 'ACTION_NEXT':
          onNext?.call();
          break;
      }
    });
  }

  Future<void> updateWidget({
    required String title,
    required String artist,
    required bool isPlaying,
    String? artPath,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'artPath': artPath,
      });
    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }

  void onSongChanged(SongEntity song, bool isPlaying) {
    updateWidget(
      title: song.title,
      artist: song.artist,
      isPlaying: isPlaying,
      artPath: song.coverArtPath,
    );
  }

  void onPlayStateChanged(bool isPlaying) {
    final lastTitle = _lastTitle;
    final lastArtist = _lastArtist;
    if (lastTitle != null) {
      updateWidget(
        title: lastTitle,
        artist: lastArtist ?? '',
        isPlaying: isPlaying,
        artPath: _lastArtPath,
      );
    }
  }

  String? _lastTitle;
  String? _lastArtist;
  String? _lastArtPath;

  void trackSong(SongEntity song) {
    _lastTitle = song.title;
    _lastArtist = song.artist;
    _lastArtPath = song.coverArtPath;
  }
}
