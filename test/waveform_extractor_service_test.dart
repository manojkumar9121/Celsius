import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celsius/services/waveform_extractor_service.dart';

const _cacheBoxName = 'waveform_cache';
const _maxEntries = 500;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('celsius_waveform_cache');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> seedLegacyEntries(int count) async {
    final box = await Hive.openBox<String>(_cacheBoxName);
    await box.putAll({
      for (var i = 0; i < count; i++)
        '/legacy-${i.toString().padLeft(3, '0')}': '0.1,0.2',
    });
    await box.close();
  }

  Future<File> writeAudioFile(String name) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(
      List<int>.generate(4096, (index) {
        return index.isEven ? 0x10 : 0x20;
      }),
    );
    return file;
  }

  test('init trims an oversized legacy cache to the cap', () async {
    await seedLegacyEntries(_maxEntries + 1);

    await WaveformExtractorService.instance.init();
    final box = Hive.box<String>(_cacheBoxName);

    expect(box.length, _maxEntries);
    expect(box.containsKey('/legacy-000'), isFalse);
    expect(box.containsKey('/legacy-001'), isTrue);
  });

  test(
    'a cache hit is retained and untouched legacy data is evicted first',
    () async {
      final entries = <String, String>{
        '/aaa-touched': '0.1,0.2',
        for (var i = 0; i < _maxEntries - 1; i++)
          '/legacy-${i.toString().padLeft(3, '0')}': '0.1,0.2',
      };
      final seedBox = await Hive.openBox<String>(_cacheBoxName);
      await seedBox.putAll(entries);
      await seedBox.close();
      await WaveformExtractorService.instance.init();

      final touched = await WaveformExtractorService.instance.extractWaveform(
        '/aaa-touched',
      );
      final newFile = await writeAudioFile('new.wav');
      await WaveformExtractorService.instance.extractWaveform(newFile.path);
      final box = Hive.box<String>(_cacheBoxName);

      expect(touched, [0.1, 0.2]);
      expect(box.length, _maxEntries);
      expect(box.containsKey('/aaa-touched'), isTrue);
      expect(box.containsKey('/legacy-000'), isFalse);
      expect(box.containsKey(newFile.path), isTrue);
    },
  );

  test('cache-hit recency survives Hive close and service reinit', () async {
    final entries = <String, String>{
      '/aaa-touched': '0.1,0.2',
      for (var i = 0; i < _maxEntries - 1; i++)
        '/legacy-${i.toString().padLeft(3, '0')}': '0.1,0.2',
    };
    final seedBox = await Hive.openBox<String>(_cacheBoxName);
    await seedBox.putAll(entries);
    await seedBox.close();
    await WaveformExtractorService.instance.init();

    await WaveformExtractorService.instance.extractWaveform('/aaa-touched');
    await Hive.close();
    await WaveformExtractorService.instance.init();

    final newFile = await writeAudioFile('after-restart.wav');
    await WaveformExtractorService.instance.extractWaveform(newFile.path);
    final box = Hive.box<String>(_cacheBoxName);

    expect(box.length, _maxEntries);
    expect(box.containsKey('/aaa-touched'), isTrue);
    expect(box.containsKey('/legacy-000'), isFalse);
    expect(box.containsKey(newFile.path), isTrue);
  });
}
