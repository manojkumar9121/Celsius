import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/data/local_storage/playlist_box.dart';
import 'package:celsius/data/local_storage/song_box.dart';
import 'package:celsius/domain/entities/playlist_entity.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/presentation/providers/library_provider.dart';
import 'package:celsius/presentation/providers/playlist_provider.dart';

class _RecordingAudioNotifier extends AudioPlayerNotifier {
  final List<List<String>> removals = [];
  Object? removalError;

  @override
  Future<void> handleSongsRemoved(List<String> ids) async {
    removals.add(List.of(ids));
    if (removalError != null) throw removalError!;
  }
}

class _SilentPlaylistNotifier extends PlaylistNotifier {
  int reloadCalls = 0;

  _SilentPlaylistNotifier() : super(autoLoad: false);

  @override
  Future<void> reload() async {
    reloadCalls++;
  }
}

class _TestLibraryNotifier extends LibraryNotifier {
  _TestLibraryNotifier(super.ref) : super(initialize: false);

  void seed(List<SongEntity> songs) {
    state = state.copyWith(songs: songs);
  }
}

SongBox _song(String id) => SongBox.fromEntity(
  SongEntity(id: id, title: id, filePath: '/music/$id.mp3'),
);

PlaylistBox _playlist() => PlaylistBox.fromEntity(
  PlaylistEntity(
    id: 'playlist-1',
    name: 'Playlist',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    songIds: const ['song-1'],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late ProviderContainer container;
  late _TestLibraryNotifier library;
  late _RecordingAudioNotifier audio;
  late _SilentPlaylistNotifier playlists;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'celsius_library_cleanup_test',
    );
    Hive.init(tempDir.path);
    HiveStorage.resetSettingsCache();
    await HiveStorage.init();
    container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith((ref) {
          library = _TestLibraryNotifier(ref);
          return library;
        }),
        audioPlayerStateProvider.overrideWith((ref) {
          audio = _RecordingAudioNotifier();
          return audio;
        }),
        playlistProvider.overrideWith((ref) {
          playlists = _SilentPlaylistNotifier();
          return playlists;
        }),
      ],
    );
    container.read(libraryProvider);
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('favorite failure leaves the last committed library value', () async {
    final song = const SongEntity(
      id: 'song-1',
      title: 'Song 1',
      filePath: '/music/song-1.mp3',
    );
    library.seed([song]);
    await Hive.box<dynamic>('songs').close();

    await expectLater(
      library.toggleFavorite(song.id),
      throwsA(isA<HiveError>()),
    );

    expect(library.state.songs.single.isFavorite, isFalse);
  });

  test('storage failure does not attempt dependent cleanup', () async {
    library.seed([
      const SongEntity(
        id: 'song-1',
        title: 'Song 1',
        filePath: '/music/song-1.mp3',
      ),
    ]);
    await Hive.box<dynamic>('songs').close();

    final result = await library.removeSong('song-1');

    expect(result.storageError, isNotNull);
    expect(result.playlistError, isNull);
    expect(result.audioError, isNull);
    expect(audio.removals, isEmpty);
    expect(playlists.reloadCalls, 0);
  });

  test('playlist cleanup failure still attempts audio queue cleanup', () async {
    await HiveStorage.addSong(_song('song-1'));
    await HiveStorage.addPlaylist(_playlist());
    library.seed([
      const SongEntity(
        id: 'song-1',
        title: 'Song 1',
        filePath: '/music/song-1.mp3',
      ),
    ]);
    await Hive.box<dynamic>('playlists').close();

    final result = await library.removeSong('song-1');

    expect(result.storageError, isNull);
    expect(result.playlistError, isNotNull);
    expect(result.audioError, isNull);
    expect(audio.removals, [
      ['song-1'],
    ]);
    expect(HiveStorage.getSong('song-1'), isNull);
  });

  test(
    'audio cleanup failure is reported separately after successful prune',
    () async {
      await HiveStorage.addSong(_song('song-1'));
      await HiveStorage.addPlaylist(_playlist());
      library.seed([
        const SongEntity(
          id: 'song-1',
          title: 'Song 1',
          filePath: '/music/song-1.mp3',
        ),
      ]);
      (container.read(audioPlayerStateProvider.notifier)
              as _RecordingAudioNotifier)
          .removalError = StateError(
        'queue failed',
      );

      final result = await library.removeSong('song-1');

      expect(result.storageError, isNull);
      expect(result.playlistError, isNull);
      expect(result.audioError, isNotNull);
      expect(playlists.reloadCalls, 1);
      expect(HiveStorage.getSong('song-1'), isNull);
      expect(HiveStorage.getPlaylist('playlist-1')!.songIds, isEmpty);
    },
  );
}
