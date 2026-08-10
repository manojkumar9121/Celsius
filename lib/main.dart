import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';
import 'package:celsuis/services/background_audio_service.dart';
import 'package:celsuis/services/widget_service.dart';
import 'package:celsuis/services/waveform_extractor_service.dart';
import 'package:celsuis/presentation/providers/audio_player_provider.dart';
import 'package:celsuis/app.dart';
import 'package:celsuis/core/widgets/app_error_boundary.dart';

AudioPlayerHandler? _audioHandlerRef;

AudioPlayerHandler? get audioHandler => _audioHandlerRef;

final ProviderContainer appContainer = ProviderContainer();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  bool hiveOk = false;
  try {
    await Hive.initFlutter();
    await HiveStorage.init();
    await WaveformExtractorService.instance.init();
    hiveOk = true;
    markHiveInitSuccess();
  } catch (e) {
    debugPrint('Hive init error: $e');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!hiveOk) {
        runApp(
          UncontrolledProviderScope(
            container: appContainer,
            child: HiveErrorScreen(error: e.toString()),
          ),
        );
      }
    });
  }

  try {
    WidgetService().init();
  } catch (e) {
    debugPrint('WidgetService init error: $e');
  }

  runApp(
    UncontrolledProviderScope(
      container: appContainer,
      child: const AppRoot(child: CelsuisApp()),
    ),
  );

  unawaited(_initAudioStack());
}

Future<void> _initAudioStack() async {
  if (Platform.isAndroid) {
    try {
      await Permission.notification.request();
    } catch (e) {
      debugPrint('Notification permission request error: $e');
    }
  }

  try {
    final settings = HiveStorage.getSettings();
    final handler = await AudioService.init(
      builder: () => AudioPlayerHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.celsuis.celsuis.channel.audio',
        androidNotificationChannelName: 'Celsuis Playback',
        androidNotificationChannelDescription: 'Audio playback controls',
        androidNotificationOngoing: settings.notificationOngoing,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_notification',
        androidNotificationClickStartsActivity: true,
        notificationColor: const Color(0xFFFF6B6B),
      ),
    ).timeout(const Duration(seconds: 15));
    _audioHandlerRef = handler;
    appContainer.read(audioHandlerProvider.notifier).state = _audioHandlerRef;
  } catch (e) {
    debugPrint('AudioService init error: $e');
  }
}
