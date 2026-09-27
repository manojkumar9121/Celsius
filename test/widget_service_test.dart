import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/services/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.celsius.celsius/widget');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('widget metadata follows replacement and explicit clearing', (
    tester,
  ) async {
    final calls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'updateWidget') {
            calls.add(Map<Object?, Object?>.from(call.arguments as Map));
          }
          return null;
        });
    final service = WidgetService();
    final song = SongEntity(
      id: 'B',
      title: 'Replacement',
      artist: 'New Artist',
      filePath: '/music/b.mp3',
      coverArtPath: '/covers/b.jpg',
    );

    service.onSongChanged(song, false);
    await tester.pump();
    service.onPlayStateChanged(true);
    await tester.pump();
    service.onSongCleared();
    await tester.pump();

    expect(calls, hasLength(3));
    expect(calls[0]['title'], 'Replacement');
    expect(calls[0]['artist'], 'New Artist');
    expect(calls[0]['artPath'], '/covers/b.jpg');
    expect(calls[1]['title'], 'Replacement');
    expect(calls[1]['isPlaying'], isTrue);
    expect(calls[2]['title'], 'No song playing');
    expect(calls[2]['isPlaying'], isFalse);
    expect(calls[2]['artPath'], isNull);
  });
}
