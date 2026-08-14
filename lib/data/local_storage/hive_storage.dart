import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsuis/data/local_storage/song_box.dart';
import 'package:celsuis/data/local_storage/playlist_box.dart';
import 'package:celsuis/data/local_storage/settings_box.dart';
import 'package:celsuis/domain/entities/app_settings.dart';

/// Current schema version for the songs box. Bump this when adding new Hive fields.
const int _kCurrentSchemaVersion = 1;

class HiveStorage {
  static const String _songsBoxName = 'songs';
  static const String _playlistsBoxName = 'playlists';
  static const String _settingsBoxName = 'settings';
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<void> init() async {
    Hive.registerAdapter(SongBoxAdapter());
    Hive.registerAdapter(PlaylistBoxAdapter());
    Hive.registerAdapter(SettingsBoxAdapter());
    await Hive.openBox<SongBox>(_songsBoxName);
    await Hive.openBox<PlaylistBox>(_playlistsBoxName);
    await Hive.openBox<SettingsBox>(_settingsBoxName);
    await _migrateHiveSchema();
    await _ensureDefaultSettings();
    _initialized = true;
  }

  static Future<void> _migrateHiveSchema() async {
    final songsBox = Hive.isBoxOpen(_songsBoxName) ? Hive.box<SongBox>(_songsBoxName) : null;

    if (songsBox == null || songsBox.isEmpty) return;

    // Check if any song needs migration (has schemaVersion < current)
    bool needsMigration = false;
    for (final key in songsBox.keys.toList()) {
      final song = songsBox.get(key);
      if (song != null && song.schemaVersion < _kCurrentSchemaVersion) {
        needsMigration = true;
        break;
      }
    }
    if (!needsMigration) return;

    // Apply migration: update schemaVersion on all songs that need it
    for (final key in songsBox.keys.toList()) {
      final song = songsBox.get(key);
      if (song == null) continue;
      if (song.schemaVersion < _kCurrentSchemaVersion) {
        song.schemaVersion = _kCurrentSchemaVersion;
        await song.save();
      }
    }
  }

  static Box<SongBox>? get songsBox {
    if (!_initialized) return null;
    return Hive.box<SongBox>(_songsBoxName);
  }

  static Box<PlaylistBox>? get playlistsBox {
    if (!_initialized) return null;
    return Hive.box<PlaylistBox>(_playlistsBoxName);
  }

  static Box<SettingsBox>? get settingsBox {
    if (!_initialized) return null;
    return Hive.box<SettingsBox>(_settingsBoxName);
  }

  // Song operations
  static Future<void> addSong(SongBox song) async {
    await songsBox?.put(song.id, song);
  }

  static Future<void> updateSong(SongBox song) async {
    await songsBox?.put(song.id, song);
  }

  static Future<void> deleteSong(String id) async {
    final song = songsBox?.get(id);
    await songsBox?.delete(id);
    // Clear waveform cache entry for the deleted song
    if (song != null && song.filePath.isNotEmpty) {
      _clearWaveformCacheEntry(song.filePath);
    }
  }

  static Future<void> deleteSongs(List<String> ids) async {
    for (final id in ids) {
      final song = songsBox?.get(id);
      await songsBox?.delete(id);
      if (song != null && song.filePath.isNotEmpty) {
        _clearWaveformCacheEntry(song.filePath);
      }
    }
  }

  static void _clearWaveformCacheEntry(String filePath) {
    try {
      final cacheDir = '${filePath}_waveform_cache';
      // Remove waveform cache file if it exists alongside the song
      final cacheFile = File('$cacheDir.bin');
      if (cacheFile.existsSync()) {
        cacheFile.deleteSync();
      }
    } catch (_) {}
  }

  static Future<void> clearAllSongs() async {
    await songsBox?.clear();
  }

  static List<SongBox> getAllSongs() {
    return songsBox?.values.toList() ?? [];
  }

  static SongBox? getSong(String id) {
    return songsBox?.get(id);
  }

  static Future<void> incrementPlayCount(String id) async {
    final song = songsBox?.get(id);
    if (song != null) {
      song.playCount++;
      song.lastPlayedAt = DateTime.now().millisecondsSinceEpoch;
      await song.save();
    }
  }

  static Future<void> toggleFavorite(String id) async {
    final song = songsBox?.get(id);
    if (song != null) {
      song.isFavorite = !song.isFavorite;
      await song.save();
    }
  }

  static List<SongBox> getFavoriteSongs() {
    return songsBox?.values.where((s) => s.isFavorite).toList() ?? [];
  }

  // Playlist operations
  static Future<void> addPlaylist(PlaylistBox playlist) async {
    await playlistsBox?.put(playlist.id, playlist);
  }

  static Future<void> updatePlaylist(PlaylistBox playlist) async {
    await playlistsBox?.put(playlist.id, playlist);
  }

  static Future<void> deletePlaylist(String id) async {
    await playlistsBox?.delete(id);
  }

  static List<PlaylistBox> getAllPlaylists() {
    return playlistsBox?.values.toList() ?? [];
  }

  static PlaylistBox? getPlaylist(String id) {
    return playlistsBox?.get(id);
  }

  // Settings operations
  static Future<void> saveSettings(AppSettings settings) async {
    if (!_initialized) return;
    final box = SettingsBox.fromSettings(settings);
    await settingsBox?.put('app_settings', box);
    await settingsBox?.flush();
  }

  static AppSettings getSettings() {
    if (!_initialized) return const AppSettings();
    final box = settingsBox?.get('app_settings');
    if (box != null) {
      return box.toSettings();
    }
    return const AppSettings();
  }

  // Folder operations
  static Future<void> addManagedFolder(String path) async {
    final settings = getSettings();
    if (!settings.managedFolders.contains(path)) {
      final updated = settings.copyWith(managedFolders: [...settings.managedFolders, path]);
      await saveSettings(updated);
    }
  }

  static Future<void> removeManagedFolder(String path) async {
    final settings = getSettings();
    final updated = settings.copyWith(managedFolders: settings.managedFolders.where((p) => p != path).toList());
    await saveSettings(updated);
  }

  static Future<void> _ensureDefaultSettings() async {
    if (settingsBox?.get('app_settings') == null) {
      await saveSettings(const AppSettings());
    }
  }
}
