import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/services/lyrics_service.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  Future<String?>? _lyricsFuture;
  String? _lyricsSongId;

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(audioPlayerProvider).currentSong;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    if (song == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Now Playing', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(child: Text('No song playing', style: TextStyle(color: textColor))),
      );
    }

    if (_lyricsSongId != song.id) {
      _lyricsSongId = song.id;
      _lyricsFuture = _fetchLyrics(song);
    }

    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: textColor),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Now Playing', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: FutureBuilder<String?>(
            future: _lyricsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: textColor.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text('Searching for lyrics...', style: TextStyle(color: textColor.withValues(alpha: 0.5))),
                  ],
                ),
              );
            }

            final lyrics = snapshot.data;
            if (lyrics == null || lyrics.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lyrics, size: 64, color: textColor.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('No lyrics available', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      '${song.title}\n${song.artist}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 14),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                lyrics,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.8),
                  fontSize: 17,
                  height: 1.8,
                ),
              ),
            );
          },
          ),
        ),
    );
  }

  Future<String?> _fetchLyrics(SongEntity song) async {
    final lyricsService = LyricsService();
    return lyricsService.getLyrics(song.realPath ?? song.filePath);
  }
}
