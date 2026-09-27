import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/presentation/providers/audio_player_provider.dart';
import 'package:celsius/presentation/providers/settings_provider.dart';
import 'package:celsius/services/background_audio_service.dart';

class _RecordingHandler extends AudioPlayerHandler {
  _RecordingHandler() : super(initialSettings: const AppSettings());

  AppSettings? runtimeSettings;
  bool playing = true;
  int pauseCalls = 0;
  int stopCalls = 0;
  bool failPause = false;
  bool failStop = false;

  @override
  bool get isPlaying => playing;

  @override
  void updateRuntimeSettings(AppSettings settings) {
    runtimeSettings = settings;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (failPause) throw StateError('pause failed');
    playing = false;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (failStop) throw StateError('stop failed');
    playing = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late _RecordingHandler handler;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'celsius_settings_runtime_test',
    );
    Hive.init(tempDir.path);
    HiveStorage.resetSettingsCache();
    await HiveStorage.init();
    handler = _RecordingHandler();
    container = ProviderContainer();
    container.read(audioPlayerStateProvider);
    container.read(audioHandlerProvider.notifier).state = handler;
  });

  tearDown(() async {
    container.dispose();
    handler.dispose();
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('committed settings reach the handler as the exact snapshot', () async {
    final settings = container.read(settingsProvider.notifier);
    await settings.toggleCrossfade(true);
    await settings.setCrossfadeDuration(850);

    expect(handler.runtimeSettings?.crossfadeEnabled, isTrue);
    expect(handler.runtimeSettings?.crossfadeDurationMs, 850);
  });

  test('committed stop-on-pause controls the runtime pause action', () async {
    final settings = container.read(settingsProvider.notifier);
    await settings.toggleStopOnPause(false);

    final paused = await container
        .read(audioPlayerStateProvider.notifier)
        .pause();

    expect(paused, isTrue);
    expect(handler.pauseCalls, 1);
    expect(handler.stopCalls, 0);
  });

  test('stop failure is also reported by the pause contract', () async {
    handler.failStop = true;

    final paused = await container
        .read(audioPlayerStateProvider.notifier)
        .pause();

    expect(paused, isFalse);
    expect(handler.stopCalls, 1);
    expect(handler.pauseCalls, 0);
  });

  test('pause reports native failure instead of claiming success', () async {
    await container.read(settingsProvider.notifier).toggleStopOnPause(false);
    handler.failPause = true;

    final paused = await container
        .read(audioPlayerStateProvider.notifier)
        .pause();

    expect(paused, isFalse);
    expect(handler.pauseCalls, 1);
    expect(handler.stopCalls, 0);
  });
}
