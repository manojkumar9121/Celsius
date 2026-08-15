import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celsuis/data/local_storage/song_box.dart';
import 'package:celsuis/domain/entities/song_entity.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('celsuis_song_box_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(SongBoxAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('SongBox round-trips schemaVersion through the adapter', () async {
    final box = await Hive.openBox<SongBox>('song_roundtrip');
    addTearDown(() => box.close());

    final song = SongBox.fromEntity(SongEntity(
      id: 'song_1',
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 240000,
      filePath: '/music/test.mp3',
      dateAdded: DateTime(2026, 1, 1),
    ));
    song.schemaVersion = 7; // non-default value proves it is serialized
    await box.put(song.id, song);

    final restored = box.get('song_1');
    expect(restored, isNotNull);
    expect(restored!.schemaVersion, 7);
    expect(restored.title, 'Test Song');
    expect(restored.durationMs, 240000);
    expect(restored.playCount, 0);
  });

  test('SongBox defaults when a stored value is missing', () async {
    final box = await Hive.openBox<SongBox>('song_defaults');
    addTearDown(() => box.close());

    final song = SongBox()
      ..id = 'song_2'
      ..title = 'T'
      ..artist = 'A'
      ..album = 'AL'
      ..durationMs = 1000
      ..filePath = '/x.mp3'
      ..timestampAdded = 0
      ..playCount = 0
      ..isFavorite = false;
    await box.put(song.id, song);

    final restored = box.get('song_2')!;
    expect(restored.schemaVersion, 1); // default, not a crash
  });

  test('legacy rows without the schemaVersion field still load (upgrade path)',
      () {
    // Simulates a song persisted by a build predating field 12: the frame
    // holds fields 0-11 but no field 12. Reads of old libraries must not
    // crash — the missing field decodes to the default (0, pre-schema).
    final adapter = SongBoxAdapter();
    final song = adapter.read(_LegacyBinaryReader());
    expect(song.id, 'legacy-song-id');
    expect(song.title, 'Legacy Title');
    expect(song.durationMs, 180000);
    expect(song.schemaVersion, 0); // defaultValue of @HiveField(12)
  });
}

/// Feeds [SongBoxAdapter.read] a frame written by the old adapter: all fields
/// 0-11 present, field 12 (schemaVersion) absent.
class _LegacyBinaryReader implements BinaryReader {
  static const Map<int, dynamic> _fields = {
    0: 'legacy-song-id',
    1: 'Legacy Title',
    2: 'Legacy Artist',
    3: 'Legacy Album',
    4: 180000,
    5: '/music/legacy.mp3',
    6: 0, // timestampAdded
    7: null, // lastPlayedAt (nullable)
    8: 3, // playCount
    9: false, // isFavorite
    10: null, // coverArtPath (nullable)
    11: null, // realPath (nullable)
  };

  bool _headerRead = false;
  int _fieldIndex = -1;

  @override
  int readByte() {
    if (!_headerRead) {
      _headerRead = true;
      return _fields.length; // numOfFields
    }
    _fieldIndex++;
    return _fieldIndex;
  }

  @override
  dynamic read([int? len]) => _fields[_fieldIndex];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected reader call: $invocation');
}
