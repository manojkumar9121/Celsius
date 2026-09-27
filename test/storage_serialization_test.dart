import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/data/local_storage/playlist_box.dart';
import 'package:celsius/data/local_storage/song_box.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/domain/entities/playlist_entity.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/services/background_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'celsius_storage_queue_test',
    );
    Hive.init(tempDir.path);
    HiveStorage.resetSettingsCache();
    await HiveStorage.init();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  SongBox song(String id) => SongBox.fromEntity(
    SongEntity(id: id, title: 'Song $id', filePath: '/music/$id.mp3'),
  );

  PlaylistBox playlist(String id, List<String> songIds) =>
      PlaylistBox.fromEntity(
        PlaylistEntity(
          id: id,
          name: 'Playlist $id',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          songIds: songIds,
        ),
      );

  Map<String, dynamic> readRawSettings() {
    final raw = Hive.box<dynamic>('settings').get('app_settings') as String;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test(
    'song field updates share one FIFO and preserve unrelated changes',
    () async {
      await HiveStorage.addSong(song('song-1'));

      final updates = <Future<dynamic>>[
        for (var i = 0; i < 20; i++) HiveStorage.incrementPlayCount('song-1'),
        HiveStorage.setFavorite('song-1', true),
        HiveStorage.updateSongDuration('song-1', 240000),
        HiveStorage.updateSongCoverArt('song-1', '/covers/song-1.jpg'),
      ];
      await Future.wait(updates);

      final stored = HiveStorage.getSong('song-1');
      expect(stored, isNotNull);
      expect(stored!.playCount, 20);
      expect(stored.isFavorite, isTrue);
      expect(stored.durationMs, 240000);
      expect(stored.coverArtPath, '/covers/song-1.jpg');
    },
  );

  test('stale field updates cannot resurrect a deleted song', () async {
    await HiveStorage.addSong(song('song-1'));
    await HiveStorage.deleteSongs(['song-1']);

    expect(await HiveStorage.incrementPlayCount('song-1'), isNull);
    expect(await HiveStorage.updateSongDuration('song-1', 1234), isNull);
    expect(
      await HiveStorage.updateSongCoverArt('song-1', '/covers/stale.jpg'),
      isNull,
    );
    expect(HiveStorage.getSong('song-1'), isNull);
  });

  test('playlist field edits merge instead of overwriting snapshots', () async {
    await Future.wait([
      HiveStorage.addSong(song('song-1')),
      HiveStorage.addSong(song('song-2')),
      HiveStorage.addSong(song('song-3')),
    ]);
    await HiveStorage.addPlaylist(playlist('playlist-1', ['song-1', 'song-2']));

    await Future.wait([
      HiveStorage.renamePlaylist('playlist-1', 'Renamed'),
      HiveStorage.addSongToPlaylist('playlist-1', 'song-3'),
      HiveStorage.removeSongFromPlaylist('playlist-1', 'song-1'),
      HiveStorage.setPlaylistCoverArt('playlist-1', '/covers/playlist.jpg'),
    ]);

    final stored = HiveStorage.getPlaylist('playlist-1');
    expect(stored, isNotNull);
    expect(stored!.name, 'Renamed');
    expect(stored.songIds, ['song-2', 'song-3']);
    expect(stored.coverArtPath, '/covers/playlist.jpg');
  });

  test('playlist edits cannot recreate a deleted playlist', () async {
    await HiveStorage.addSong(song('song-1'));
    await HiveStorage.addSong(song('song-2'));
    await HiveStorage.addPlaylist(playlist('playlist-1', ['song-1']));
    await HiveStorage.deletePlaylist('playlist-1');

    expect(await HiveStorage.renamePlaylist('playlist-1', 'Stale'), isNull);
    expect(await HiveStorage.addSongToPlaylist('playlist-1', 'song-2'), isNull);
    expect(HiveStorage.getPlaylist('playlist-1'), isNull);
  });

  test(
    'reorder, add, and song-deletion pruning share playlist serialization',
    () async {
      await Future.wait([
        for (var i = 1; i <= 4; i++) HiveStorage.addSong(song('song-$i')),
      ]);
      await HiveStorage.addPlaylist(
        playlist('playlist-1', ['song-1', 'song-2', 'song-3']),
      );

      await Future.wait([
        HiveStorage.reorderPlaylistSongs('playlist-1', ['song-3', 'song-1']),
        HiveStorage.addSongToPlaylist('playlist-1', 'song-4'),
      ]);
      await HiveStorage.deleteSongs(['song-2']);
      expect(
        HiveStorage.getPlaylist('playlist-1')!.songIds,
        ['song-3', 'song-1', 'song-2', 'song-4'],
        reason: 'song deletion and playlist pruning are separate outcomes',
      );
      await HiveStorage.pruneSongIdsFromPlaylists(['song-2']);

      expect(HiveStorage.getPlaylist('playlist-1')!.songIds, [
        'song-3',
        'song-1',
        'song-4',
      ]);
    },
  );

  test('rapid favorite toggles commit in invocation order', () async {
    await HiveStorage.addSong(song('song-1'));

    final results = await Future.wait([
      HiveStorage.toggleFavorite('song-1'),
      HiveStorage.toggleFavorite('song-1'),
    ]);

    expect(results.map((result) => result!.isFavorite), [true, false]);
    expect(HiveStorage.getSong('song-1')!.isFavorite, isFalse);
  });

  test('stopped queue replacement does not record a play', () async {
    await HiveStorage.addSong(song('song-1'));
    final handler = AudioPlayerHandler();
    addTearDown(handler.dispose);

    await handler.setQueue([
      SongEntity(
        id: 'song-1',
        title: 'Song song-1',
        filePath: '/music/song-1.mp3',
      ),
    ], playWhenReady: false);

    expect(HiveStorage.getSong('song-1')!.playCount, 0);
  });

  test(
    'folder and ordinary settings mutations cannot overwrite each other',
    () async {
      await HiveStorage.saveSettings(
        const AppSettings(managedFolders: ['/remove-me']),
      );

      await Future.wait([
        HiveStorage.addManagedFolder('/add-me'),
        HiveStorage.mutateSettings(
          (settings) => settings.copyWith(themePreset: ThemePreset.nord),
        ),
        HiveStorage.removeManagedFolder('/remove-me'),
      ]);

      final stored = readRawSettings();
      expect(stored['themePreset'], ThemePreset.nord.index);
      expect(stored['managedFolders'], ['/add-me']);
    },
  );

  test(
    'a failed settings write rejects without poisoning later writes',
    () async {
      await expectLater(
        HiveStorage.mutateSettings(
          (settings) => settings.copyWith(waveformAnimationSpeed: double.nan),
        ),
        throwsA(isA<FormatException>()),
      );

      final committed = await HiveStorage.mutateSettings(
        (settings) => settings.copyWith(waveformAnimationSpeed: 1.5),
      );
      expect(committed.waveformAnimationSpeed, 1.5);
      expect(readRawSettings()['waveformAnimationSpeed'], 1.5);
    },
  );
}
