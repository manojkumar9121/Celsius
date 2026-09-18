import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:celsius/app.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('celsius_test');
    Hive.init(tempDir.path);
    await HiveStorage.init();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('app builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CelsiusApp()),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final error = tester.takeException();
    if (error != null) {
      fail('STARTUP EXCEPTION:\n$error');
    }
  });
}
