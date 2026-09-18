import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:celsius/data/local_storage/song_box.dart';
import 'package:celsius/data/local_storage/playlist_box.dart';
import 'package:celsius/data/local_storage/settings_box.dart';
import 'package:celsius/domain/entities/app_settings.dart';
import 'package:celsius/domain/entities/playlist_entity.dart';
import 'package:celsius/domain/entities/song_entity.dart';
import 'package:celsius/services/waveform_extractor_service.dart';

/// Current schema version for JSON payloads. Bump this when the JSON layout
/// of stored records changes, and add the corresponding migration step in
/// [_migrateRecord] so old data is upgraded in place instead of lost.
const int _kCurrentSchemaVersion = 1;

/// Hive storage backed by JSON payloads.
///
/// Records are stored as JSON strings (built-in Hive type), so decoding can
/// never fail regardless of which build wrote them — schema changes are
/// handled by [_migrateRecord] on read, never by resetting the box.
///
/// The legacy binary adapters ([SongBoxAdapter], [PlaylistBoxAdapter],
/// [SettingsBoxAdapter]) are only used for a one-time migration of boxes
/// written by older builds; new data is always JSON.
class HiveStorage {
  static const String _songsBoxName = 'songs';
  static const String _playlistsBoxName = 'playlists';
  static const String _settingsBoxName = 'settings';
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<void> init() async {
    // Legacy adapters are still needed to DECODE data written by older
    // builds during the one-time migration. Hive keeps the adapter registry
    // across Hive.close(), so a retry (HiveErrorScreen -> Hive.close() ->
    // init()) must not re-register — re-registering a typeId throws
    // "already a type adapter".
    if (!Hive.isAdapterRegistered(SongBoxAdapter().typeId)) {
      Hive.registerAdapter(SongBoxAdapter());
    }
    if (!Hive.isAdapterRegistered(PlaylistBoxAdapter().typeId)) {
      Hive.registerAdapter(PlaylistBoxAdapter());
    }
    if (!Hive.isAdapterRegistered(SettingsBoxAdapter().typeId)) {
      Hive.registerAdapter(SettingsBoxAdapter());
    }
    await _openBoxOrReset(_songsBoxName);
    await _openBoxOrReset(_playlistsBoxName);
    await _openBoxOrReset(_settingsBoxName);
    await _migrateLegacyBoxes();
    _initialized = true;
    await _ensureDefaultSettings();
  }

  /// Opens a box (untyped: values are JSON strings). Only a truly corrupted
  /// file (garbage bytes, wrong checksum) is reset — schema drift can no
  /// longer break opening, because JSON always decodes.
  static Future<void> _openBoxOrReset(String name) async {
    try {
      await Hive.openBox<dynamic>(name);
    } catch (e) {
      debugPrint('Box "$name" failed to open ($e) — resetting it');
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (e2) {
        debugPrint('Failed to delete box "$name" from disk: $e2');
      }
      await Hive.openBox<dynamic>(name);
    }
  }

  /// One-time migration: boxes written by older builds contain typed binary
  /// frames (SongBox/PlaylistBox/SettingsBox objects) instead of JSON
  /// strings. Rewrite every record in place as JSON so it survives forever.
  static Future<void> _migrateLegacyBoxes() async {
    await _migrateBox(_songsBoxName, (value) {
      if (value is SongBox) {
        return jsonEncode({'schemaVersion': _kCurrentSchemaVersion, ...value.toEntity().toJson()});
      }
      return null;
    });
    await _migrateBox(_playlistsBoxName, (value) {
      if (value is PlaylistBox) {
        return jsonEncode({'schemaVersion': _kCurrentSchemaVersion, ...value.toEntity().toJson()});
      }
      return null;
    });
    await _migrateBox(_settingsBoxName, (value) {
      if (value is SettingsBox) {
        return jsonEncode({'schemaVersion': _kCurrentSchemaVersion, ...value.toSettings().toJson()});
      }
      return null;
    });
  }

  /// Rewrites legacy typed records in [name] as JSON strings. Records that
  /// are neither JSON nor a known legacy type are skipped (dropped) rather
  /// than crashing the app.
  static Future<void> _migrateBox(String name, String? Function(dynamic value) encode) async {
    final box = Hive.box<dynamic>(name);
    for (final key in box.keys.toList()) {
      final value = box.get(key);
      if (value is String) continue; // already JSON
      try {
        final encoded = encode(value);
        if (encoded != null) {
          debugPrint('Migrating legacy record "$key" in "$name" to JSON');
          await box.put(key, encoded);
        } else {
          debugPrint('Skipping unreadable record "$key" in "$name"');
          await box.delete(key);
        }
      } catch (e) {
        debugPrint('Skipping unreadable record "$key" in "$name": $e');
        await box.delete(key);
      }
    }
  }

  // JSON encoding / decoding helpers --------------------------------------

  static String? _safeEncode(Map<String, dynamic> json) {
    try {
      return jsonEncode({'schemaVersion': _kCurrentSchemaVersion, ...json});
    } catch (e) {
      debugPrint('Failed to encode record: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _safeDecode(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _migrateRecord(decoded);
    } catch (e) {
      debugPrint('Skipping undecodable record: $e');
      return null;
    }
  }

  /// Applies schema migrations based on the record's stored [schemaVersion].
  /// New migrations go here as the schema evolves; old data is upgraded in
  /// place instead of being reset.
  static Map<String, dynamic> _migrateRecord(Map<String, dynamic> record) {
    final version = (record['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version == _kCurrentSchemaVersion) return record;
    debugPrint('Migrating record from schema $version to $_kCurrentSchemaVersion');
    // Future migrations go here, e.g.:
    // if (version < 2) { record['newField'] = record.remove('oldField'); }
    return record;
  }

  static Box<dynamic>? get songsBox {
    if (!_initialized) return null;
    return Hive.box<dynamic>(_songsBoxName);
  }

  static Box<dynamic>? get playlistsBox {
    if (!_initialized) return null;
    return Hive.box<dynamic>(_playlistsBoxName);
  }

  static Box<dynamic>? get settingsBox {
    if (!_initialized) return null;
    return Hive.box<dynamic>(_settingsBoxName);
  }

  // Song operations
  static Future<void> addSong(SongBox song) async {
    final encoded = _safeEncode(song.toEntity().toJson());
    if (encoded != null) {
      await songsBox?.put(song.id, encoded);
    }
  }

  static Future<void> updateSong(SongBox song) async {
    final encoded = _safeEncode(song.toEntity().toJson());
    if (encoded != null) {
      await songsBox?.put(song.id, encoded);
    }
  }

  static Future<void> deleteSong(String id) async {
    final song = getSong(id);
    await songsBox?.delete(id);
    // Clear the waveform cache entry (a Hive box keyed by audio path).
    if (song != null && song.filePath.isNotEmpty) {
      await WaveformExtractorService.instance.removeFromCache(song.filePath);
    }
  }

  static Future<void> deleteSongs(List<String> ids) async {
    final pathsToRemove = <String>[];
    for (final id in ids) {
      final song = getSong(id);
      if (song != null && song.filePath.isNotEmpty) {
        pathsToRemove.add(song.filePath);
      }
    }
    await songsBox?.deleteAll(ids);
    if (pathsToRemove.isNotEmpty) {
      await Future.wait(
        pathsToRemove.map((p) => WaveformExtractorService.instance.removeFromCache(p)),
        eagerError: false,
      );
    }
  }

  static Future<void> clearAllSongs() async {
    await songsBox?.clear();
  }

  static List<SongBox> getAllSongs() {
    final box = songsBox;
    if (box == null) return [];
    final result = <SongBox>[];
    for (final key in box.keys.toList()) {
      final record = _safeDecode(box.get(key) as String?);
      if (record == null) continue;
      try {
        result.add(SongBox.fromEntity(SongEntity.fromJson(record)));
      } catch (e) {
        debugPrint('Skipping unreadable song record $key: $e');
      }
    }
    return result;
  }

  static SongBox? getSong(String id) {
    final box = songsBox;
    if (box == null) return null;
    final record = _safeDecode(box.get(id) as String?);
    if (record == null) return null;
    try {
      return SongBox.fromEntity(SongEntity.fromJson(record));
    } catch (e) {
      debugPrint('Skipping unreadable song record $id: $e');
      return null;
    }
  }

  static Future<void> incrementPlayCount(String id) async {
    final song = getSong(id);
    if (song != null) {
      song.playCount++;
      song.lastPlayedAt = DateTime.now().millisecondsSinceEpoch;
      await updateSong(song);
    }
  }

  static Future<void> toggleFavorite(String id) async {
    final song = getSong(id);
    if (song != null) {
      song.isFavorite = !song.isFavorite;
      await updateSong(song);
    }
  }

  static List<SongBox> getFavoriteSongs() {
    return getAllSongs().where((s) => s.isFavorite).toList();
  }

  // Playlist operations
  static Future<void> addPlaylist(PlaylistBox playlist) async {
    final encoded = _safeEncode(playlist.toEntity().toJson());
    if (encoded != null) {
      await playlistsBox?.put(playlist.id, encoded);
    }
  }

  static Future<void> updatePlaylist(PlaylistBox playlist) async {
    final encoded = _safeEncode(playlist.toEntity().toJson());
    if (encoded != null) {
      await playlistsBox?.put(playlist.id, encoded);
    }
  }

  static Future<void> deletePlaylist(String id) async {
    await playlistsBox?.delete(id);
  }

  static List<PlaylistBox> getAllPlaylists() {
    final box = playlistsBox;
    if (box == null) return [];
    final result = <PlaylistBox>[];
    for (final key in box.keys.toList()) {
      final record = _safeDecode(box.get(key) as String?);
      if (record == null) continue;
      try {
        result.add(PlaylistBox.fromEntity(PlaylistEntity.fromJson(record)));
      } catch (e) {
        debugPrint('Skipping unreadable playlist record $key: $e');
      }
    }
    return result;
  }

  static PlaylistBox? getPlaylist(String id) {
    final box = playlistsBox;
    if (box == null) return null;
    final record = _safeDecode(box.get(id) as String?);
    if (record == null) return null;
    try {
      return PlaylistBox.fromEntity(PlaylistEntity.fromJson(record));
    } catch (e) {
      debugPrint('Skipping unreadable playlist record $id: $e');
      return null;
    }
  }

  // Settings operations
  static Future<void> saveSettings(AppSettings settings) async {
    if (!_initialized) return;
    final encoded = _safeEncode(settings.toJson());
    if (encoded != null) {
      _cachedSettings = settings;
      await settingsBox?.put('app_settings', encoded);
      await settingsBox?.flush();
    }
  }

  static AppSettings? _cachedSettings;

  /// Clears the in-memory settings cache. Intended for tests that need a
  /// fresh read from storage between cases.
  static void resetSettingsCache() => _cachedSettings = null;

  static AppSettings getSettings() {
    if (!_initialized) return const AppSettings();
    final cached = _cachedSettings;
    if (cached != null) return cached;
    final box = settingsBox;
    if (box == null) return const AppSettings();
    final record = _safeDecode(box.get('app_settings') as String?);
    if (record == null) return const AppSettings();
    try {
      final settings = AppSettings.fromJson(record);
      _cachedSettings = settings;
      return settings;
    } catch (e) {
      debugPrint('Settings decode failed ($e) — using defaults');
      return const AppSettings();
    }
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
    final box = settingsBox;
    if (box == null) return;
    final raw = box.get('app_settings');
    if (raw == null) {
      await saveSettings(const AppSettings());
      return;
    }
    // A stored record that can't be parsed (written by an incompatible
    // schema) is dropped and replaced with defaults instead of failing init.
    if (_safeDecode(raw as String?) == null) {
      debugPrint('Settings record unreadable — resetting to defaults');
      try {
        await box.delete('app_settings');
      } catch (_) {}
      await saveSettings(const AppSettings());
      return;
    }
    // Warm the cache so subsequent getSettings() calls are free.
    _cachedSettings = AppSettings.fromJson(_safeDecode(raw)!);
  }
}