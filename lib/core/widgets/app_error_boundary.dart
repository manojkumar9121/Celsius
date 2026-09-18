import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsius/data/local_storage/hive_storage.dart';
import 'package:celsius/app.dart';

bool _hiveInitSuccess = false;
String _hiveErrorText = 'Local storage failed to initialize.';

void markHiveInitSuccess() => _hiveInitSuccess = true;

/// Records the real initialization failure so the error screen shows the
/// actual cause instead of a generic message.
void reportHiveInitError(Object error) {
  _hiveErrorText = 'Local storage failed to initialize.\n\n$error';
}

class HiveErrorScreen extends StatelessWidget {
  final String error;
  const HiveErrorScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF1A1A2E), const Color(0xFF121212)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.storage_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Storage Error',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await Hive.close();
                      await Hive.initFlutter();
                      await HiveStorage.init();
                      markHiveInitSuccess();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const CelsiusApp()),
                          (_) => false,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Retry failed: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppRoot extends ConsumerWidget {
  final Widget child;
  const AppRoot({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_hiveInitSuccess) {
      // HiveErrorScreen uses Scaffold/Text/FilledButton and needs a
      // MaterialApp ancestor for Directionality, themes and the Navigator
      // used by the retry flow.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HiveErrorScreen(error: _hiveErrorText),
      );
    }
    return child;
  }
}
