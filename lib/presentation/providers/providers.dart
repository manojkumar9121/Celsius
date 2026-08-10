import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:celsuis/presentation/providers/library_provider.dart';
import 'package:celsuis/presentation/providers/playlist_provider.dart';
import 'package:celsuis/presentation/providers/settings_provider.dart';

final allProviders = Provider<void>((ref) {
  ref.read(libraryProvider);
  ref.read(playlistProvider);
  ref.read(settingsProvider);
});
