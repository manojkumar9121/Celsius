import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';
import 'package:celsuis/data/local_storage/playlist_box.dart';
import 'package:celsuis/data/local_storage/settings_box.dart';
import 'package:celsuis/data/local_storage/song_box.dart';
import 'package:celsuis/domain/entities/app_settings.dart';
import 'package:celsuis/domain/entities/playlist_entity.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

/// Guards the storage upgrade path: boxes written by older builds contain
/// typed binary frames (SongBox/PlaylistBox/SettingsBox). On first launch of
/// the JSON-backed version they must be MIGRATED to JSON, not reset —
/// playlists, favorites and play counts survive.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('celsuis_migration_test');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Writes a legacy (pre-JSON) songs/playlists/settings box the way older
  /// builds did: typed binary frames via the legacy adapters.
  Future<void> seedLegacyBoxes() async {
    if (!Hive.isAdapterRegistered(SongBoxAdapter().typeId)) {
      Hive.registerAdapter(SongBoxAdapter());
    }
    if (!Hive.isAdapterRegistered(PlaylistBoxAdapter().typeId)) {
      Hive.registerAdapter(PlaylistBoxAdapter());
    }
    if (!Hive.isAdapterRegistered(SettingsBoxAdapter().typeId)) {
      Hive.registerAdapter(SettingsBoxAdapter());
    }

    final songs = await Hive.openBox<SongBox>('songs');
    await songs.put('song_1', SongBox.fromEntity(SongEntity(
      id: 'song_1',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 240000,
      filePath: '/music/test.mp3',
      playCount: 5,
      isFavorite: true,
    )));
    await songs.close();

    final playlists = await Hive.openBox<PlaylistBox>('playlists');
    await playlists.put('pl_1', PlaylistBox.fromEntity(PlaylistEntity(
      id: 'pl_1',
      name: 'Chill Mix',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      songIds: ['song_1'],
    )));
    await playlists.close();

    final settings = await Hive.openBox<SettingsBox>('settings');
    await settings.put('app_settings', SettingsBox.fromSettings(const AppSettings(
      themePreset: ThemePreset.ocean,
      autoplayEnabled: true,
    )));
    await settings.close();
  }

  test('legacy binary song/playlist/settings records migrate to JSON, not reset',
      () async {
    await seedLegacyBoxes();

    await HiveStorage.init();

    expect(HiveStorage.isInitialized, isTrue);

    // Songs survived with favorites and play counts.
    final songs = HiveStorage.getAllSongs();
    expect(songs, hasLength(1));
    expect(songs.single.id, 'song_1');
    expect(songs.single.isFavorite, isTrue);
    expect(songs.single.playCount, 5);
    expect(songs.single.durationMs, 240000);

    // Playlists survived with their song lists.
    final playlists = HiveStorage.getAllPlaylists();
    expect(playlists, hasLength(1));
    expect(playlists.single.name, 'Chill Mix');
    expect(playlists.single.songIds, ['song_1']);

    // Settings survived.
    expect(HiveStorage.getSettings().themePreset, ThemePreset.ocean);
    expect(HiveStorage.getSettings().autoplayEnabled, isTrue);
  });

  test('after migration, records are stored as JSON strings', () async {
    await seedLegacyBoxes();
    await HiveStorage.init();

    final songsBox = Hive.box<dynamic>('songs');
    final raw = songsBox.get('song_1');
    expect(raw, isA<String>());
    final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], 1);
    expect(decoded['title'], 'Test Song');
    expect(decoded['isFavorite'], isTrue);
  });

  test('migration is idempotent: a second init leaves JSON records untouched',
      () async {
    await seedLegacyBoxes();
    await HiveStorage.init();
    await Hive.close();

    await HiveStorage.init();

    expect(HiveStorage.getAllSongs(), hasLength(1));
    expect(HiveStorage.getAllPlaylists(), hasLength(1));
    expect(HiveStorage.getSettings().themePreset, ThemePreset.ocean);
  });

  test('undecodable legacy settings record resets to defaults, app still starts',
      () async {
    // Simulate data written by an incompatible older schema: a raw double
    // under the settings key stands in for a field that changed type
    // (e.g. double -> bool).
    final rawBox = await Hive.openBox('settings');
    await rawBox.put('app_settings', 1.5);
    await rawBox.close();

    await HiveStorage.init();

    expect(HiveStorage.isInitialized, isTrue);
    expect(HiveStorage.getSettings().autoplayEnabled, isTrue);
    expect(HiveStorage.getSettings().themePreset, ThemePreset.dark);
  });

  test('unreadable legacy song records are skipped, decodable ones survive',
      () async {
    if (!Hive.isAdapterRegistered(SongBoxAdapter().typeId)) {
      Hive.registerAdapter(SongBoxAdapter());
    }
    final rawBox = await Hive.openBox<dynamic>('songs');
    await rawBox.put('good-song', SongBox.fromEntity(SongEntity(
      id: 'good-song',
      title: 'Good',
      filePath: '/music/good.mp3',
    )));
    await rawBox.put('bad-song', 42); // junk that is neither JSON nor SongBox
    await rawBox.close();

    await HiveStorage.init();

    expect(HiveStorage.isInitialized, isTrue);
    final songs = HiveStorage.getAllSongs();
    expect(songs, hasLength(1));
    expect(songs.single.id, 'good-song');
  });

  test('a garbage box file is reset, app still starts', () async {
    // Corrupt the box file so Hive cannot even parse it.
    final boxFile = File('${tempDir.path}/settings.hive');
    await boxFile.writeAsBytes(List.filled(64, 0xFF));

    await HiveStorage.init();

    expect(HiveStorage.isInitialized, isTrue);
    expect(HiveStorage.getSettings().autoplayEnabled, isTrue);
  });

  test('new JSON records round-trip through getAllSongs/getPlaylist', () async {
    await HiveStorage.init();

    final song = SongBox.fromEntity(SongEntity(
      id: 'song_9',
      title: 'Round Trip',
      filePath: '/music/round.mp3',
      isFavorite: true,
      playCount: 3,
    ));
    await HiveStorage.addSong(song);
    await HiveStorage.toggleFavorite('song_9');

    final restored = HiveStorage.getSong('song_9');
    expect(restored, isNotNull);
    expect(restored!.isFavorite, isFalse); // toggled off
    expect(restored.title, 'Round Trip');

    final playlist = PlaylistBox.fromEntity(PlaylistEntity(
      id: 'pl_9',
      name: 'New',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      songIds: ['song_9'],
    ));
    await HiveStorage.addPlaylist(playlist);
    expect(HiveStorage.getPlaylist('pl_9')!.songIds, ['song_9']);
  });
}