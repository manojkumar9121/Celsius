import 'dart:async';
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

/// Serializes every read-modify-write cycle for one Hive box. The returned
/// future carries the operation's original result or error; the internal tail
/// only recovers so one failed write cannot poison later writes.
class _SerialExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

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
  static final _songWrites = _SerialExecutor();
  static final _playlistWrites = _SerialExecutor();
  static final _settingsWrites = _SerialExecutor();

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
    } catch (error) {
      if (!_isBoxCorruption(error)) rethrow;
      debugPrint('Box "$name" is corrupted ($error) — resetting it');
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (deleteError) {
        throw StateError(
          'Failed to delete corrupted box "$name": $deleteError',
        );
      }
      await Hive.openBox<dynamic>(name);
    }
  }

  static bool _isBoxCorruption(Object error) {
    if (error is FormatException) return true;
    if (error is! HiveError) return false;
    final message = error.message.toLowerCase();
    return message.contains('corrupt') ||
        message.contains('wrong checksum') ||
        message.contains('unexpected eof');
  }

  /// One-time migration: boxes written by older builds contain typed binary
  /// frames (SongBox/PlaylistBox/SettingsBox objects) instead of JSON
  /// strings. Rewrite every record in place as JSON so it survives forever.
  static Future<void> _migrateLegacyBoxes() async {
    await _migrateBox(_songsBoxName, (value) {
      if (value is SongBox) {
        return jsonEncode({
          'schemaVersion': _kCurrentSchemaVersion,
          ...value.toEntity().toJson(),
        });
      }
      return null;
    });
    await _migrateBox(_playlistsBoxName, (value) {
      if (value is PlaylistBox) {
        return jsonEncode({
          'schemaVersion': _kCurrentSchemaVersion,
          ...value.toEntity().toJson(),
        });
      }
      return null;
    });
    await _migrateBox(_settingsBoxName, (value) {
      if (value is SettingsBox) {
        return jsonEncode({
          'schemaVersion': _kCurrentSchemaVersion,
          ...value.toSettings().toJson(),
        });
      }
      return null;
    });
  }

  /// Rewrites legacy typed records in [name] as JSON strings. Records that
  /// are neither JSON nor a known legacy type are skipped (dropped) rather
  /// than crashing the app.
  static Future<void> _migrateBox(
    String name,
    String? Function(dynamic value) encode,
  ) async {
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

  static String _safeEncode(Map<String, dynamic> json) {
    try {
      return jsonEncode({'schemaVersion': _kCurrentSchemaVersion, ...json});
    } catch (error) {
      throw FormatException('Failed to encode storage record: $error');
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
    debugPrint(
      'Migrating record from schema $version to $_kCurrentSchemaVersion',
    );
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
  static Future<SongBox?> addSong(SongBox song) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      final existing = _getSongUnqueued(song.id, box);
      if (existing != null) return existing;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  /// Sets an explicit favorite value. The read and write happen in one
  /// serialized operation, so a concurrent play-count or artwork update is
  /// preserved.
  static Future<SongBox?> setFavorite(String id, bool value) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      final song = _getSongUnqueued(id, box);
      if (song == null || song.isFavorite == value) return song;
      song.isFavorite = value;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  static Future<SongBox?> toggleFavorite(String id) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      final song = _getSongUnqueued(id, box);
      if (song == null) return null;
      song.isFavorite = !song.isFavorite;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  static Future<SongBox?> incrementPlayCount(String id) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      final song = _getSongUnqueued(id, box);
      if (song == null) return null;
      song.playCount++;
      song.lastPlayedAt = DateTime.now().millisecondsSinceEpoch;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  static Future<SongBox?> updateSongDuration(String id, int durationMs) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      final song = _getSongUnqueued(id, box);
      if (song == null) return null;
      song.durationMs = durationMs;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  static Future<SongBox?> updateSongCoverArt(String id, String coverArtPath) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      final song = _getSongUnqueued(id, box);
      if (song == null) return null;
      song.coverArtPath = coverArtPath;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  /// Compatibility update for callers that still provide a full song record.
  /// Runtime metadata updates should use the field-specific methods above so
  /// unrelated concurrent changes are not overwritten.
  static Future<SongBox?> updateSong(SongBox song) {
    return _songWrites.run(() async {
      final box = _requireSongsBox();
      if (!box.containsKey(song.id)) return null;
      await _putSongUnqueued(song, box);
      return song;
    });
  }

  static Future<void> deleteSong(String id) => deleteSongs([id]);

  static Future<void> deleteSongs(List<String> ids) async {
    if (ids.isEmpty) return;
    final idSet = ids.toSet();
    final waveKeys = await _songWrites.run(() async {
      final box = _requireSongsBox();
      // Capture cache keys before deleting, since the song record is the only
      // place that knows both its content and real paths.
      final keys = <String>{};
      for (final id in idSet) {
        final song = _getSongUnqueued(id, box);
        if (song == null) continue;
        if (song.filePath.isNotEmpty) keys.add(song.filePath);
        final realPath = song.realPath;
        if (realPath != null && realPath.isNotEmpty) keys.add(realPath);
      }
      await box.deleteAll(idSet);
      return keys.toList();
    });

    if (waveKeys.isNotEmpty) {
      await Future.wait(
        waveKeys.map(WaveformExtractorService.instance.removeFromCache),
        eagerError: false,
      );
    }
  }

  static Future<void> pruneSongIdsFromPlaylists(List<String> ids) {
    return _removeSongIdsFromPlaylists(ids.toSet());
  }

  static Future<void> clearAllSongs() async {
    await _songWrites.run(() => _requireSongsBox().clear());
    try {
      await _playlistWrites.run(() async {
        final box = _requirePlaylistsBox();
        final updates = <String, String>{};
        for (final key in box.keys.toList()) {
          final playlist = _getPlaylistUnqueued(key.toString(), box);
          if (playlist == null || playlist.songIds.isEmpty) continue;
          playlist.songIds = const [];
          playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
          updates[key.toString()] = _encodePlaylist(playlist);
        }
        if (updates.isNotEmpty) await box.putAll(updates);
      });
    } finally {
      await WaveformExtractorService.instance.clearCache();
    }
  }

  static List<SongBox> getAllSongs() {
    final box = songsBox;
    if (box == null) return [];
    final result = <SongBox>[];
    for (final key in box.keys.toList()) {
      final song = _getSongUnqueued(key.toString(), box);
      if (song != null) result.add(song);
    }
    return result;
  }

  static SongBox? getSong(String id) {
    final box = songsBox;
    return box == null ? null : _getSongUnqueued(id, box);
  }

  static List<SongBox> getFavoriteSongs() {
    return getAllSongs().where((s) => s.isFavorite).toList();
  }

  static Box<dynamic> _requireSongsBox() {
    if (!_initialized) throw StateError('HiveStorage is not initialized');
    return Hive.box<dynamic>(_songsBoxName);
  }

  static SongBox? _getSongUnqueued(String id, Box<dynamic> box) {
    final record = _safeDecode(box.get(id) as String?);
    if (record == null) return null;
    try {
      return SongBox.fromEntity(SongEntity.fromJson(record));
    } catch (error) {
      debugPrint('Skipping unreadable song record $id: $error');
      return null;
    }
  }

  static Future<void> _putSongUnqueued(SongBox song, Box<dynamic> box) {
    return box.put(song.id, _safeEncode(song.toEntity().toJson()));
  }

  // Playlist operations
  static Future<PlaylistBox?> addPlaylist(PlaylistBox playlist) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      final existing = _getPlaylistUnqueued(playlist.id, box);
      if (existing != null) return existing;
      await box.put(playlist.id, _encodePlaylist(playlist));
      return playlist;
    });
  }

  /// Compatibility full-record update. Provider edits use the atomic methods
  /// below so unrelated fields are always read from the current record.
  static Future<PlaylistBox?> updatePlaylist(PlaylistBox playlist) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      if (!box.containsKey(playlist.id)) return null;
      await box.put(playlist.id, _encodePlaylist(playlist));
      return playlist;
    });
  }

  static Future<bool> deletePlaylist(String id) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      final existed = box.containsKey(id);
      await box.delete(id);
      return existed;
    });
  }

  static Future<PlaylistBox?> renamePlaylist(String id, String name) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      final playlist = _getPlaylistUnqueued(id, box);
      if (playlist == null) return null;
      playlist.name = name;
      playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.put(id, _encodePlaylist(playlist));
      return playlist;
    });
  }

  static Future<PlaylistBox?> addSongToPlaylist(
    String playlistId,
    String songId,
  ) {
    return _playlistWrites.run(() async {
      // Read the song box directly rather than nesting the song executor (song
      // deletion holds that queue while waiting for playlist pruning).
      if (getSong(songId) == null) return null;
      final box = _requirePlaylistsBox();
      final playlist = _getPlaylistUnqueued(playlistId, box);
      if (playlist == null) return null;
      if (playlist.songIds.contains(songId)) return playlist;
      playlist.songIds = [...playlist.songIds, songId];
      playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.put(playlistId, _encodePlaylist(playlist));
      return playlist;
    });
  }

  static Future<PlaylistBox?> removeSongFromPlaylist(
    String playlistId,
    String songId,
  ) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      final playlist = _getPlaylistUnqueued(playlistId, box);
      if (playlist == null) return null;
      if (!playlist.songIds.contains(songId)) return playlist;
      playlist.songIds = playlist.songIds.where((id) => id != songId).toList();
      playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.put(playlistId, _encodePlaylist(playlist));
      return playlist;
    });
  }

  static Future<PlaylistBox?> setPlaylistCoverArt(
    String playlistId,
    String coverArtPath,
  ) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      final playlist = _getPlaylistUnqueued(playlistId, box);
      if (playlist == null) return null;
      playlist.coverArtPath = coverArtPath;
      playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.put(playlistId, _encodePlaylist(playlist));
      return playlist;
    });
  }

  /// Reorders only IDs that are still present in the current stored record.
  /// Missing/deleted IDs and songs added concurrently are preserved without
  /// allowing an old UI snapshot to resurrect them.
  static Future<PlaylistBox?> reorderPlaylistSongs(
    String playlistId,
    List<String> orderedIds,
  ) {
    return _playlistWrites.run(() async {
      final box = _requirePlaylistsBox();
      final playlist = _getPlaylistUnqueued(playlistId, box);
      if (playlist == null) return null;
      final current = playlist.songIds;
      final reordered = <String>[];
      final seen = <String>{};
      for (final id in orderedIds) {
        if (current.contains(id) && seen.add(id)) reordered.add(id);
      }
      for (final id in current) {
        if (seen.add(id)) reordered.add(id);
      }
      if (_sameStringList(playlist.songIds, reordered)) return playlist;
      playlist.songIds = reordered;
      playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
      await box.put(playlistId, _encodePlaylist(playlist));
      return playlist;
    });
  }

  static Future<void> _removeSongIdsFromPlaylists(Set<String> songIds) {
    return _playlistWrites.run(() async {
      if (songIds.isEmpty) return;
      final box = _requirePlaylistsBox();
      final updates = <String, String>{};
      for (final key in box.keys.toList()) {
        final playlist = _getPlaylistUnqueued(key.toString(), box);
        if (playlist == null || !playlist.songIds.any(songIds.contains)) {
          continue;
        }
        playlist.songIds = playlist.songIds
            .where((id) => !songIds.contains(id))
            .toList();
        playlist.timestampUpdated = DateTime.now().millisecondsSinceEpoch;
        updates[key.toString()] = _encodePlaylist(playlist);
      }
      if (updates.isNotEmpty) await box.putAll(updates);
    });
  }

  static List<PlaylistBox> getAllPlaylists() {
    final box = playlistsBox;
    if (box == null) return [];
    final result = <PlaylistBox>[];
    for (final key in box.keys.toList()) {
      final playlist = _getPlaylistUnqueued(key.toString(), box);
      if (playlist != null) result.add(playlist);
    }
    return result;
  }

  static PlaylistBox? getPlaylist(String id) {
    final box = playlistsBox;
    return box == null ? null : _getPlaylistUnqueued(id, box);
  }

  static Box<dynamic> _requirePlaylistsBox() {
    if (!_initialized) throw StateError('HiveStorage is not initialized');
    return Hive.box<dynamic>(_playlistsBoxName);
  }

  static PlaylistBox? _getPlaylistUnqueued(String id, Box<dynamic> box) {
    final record = _safeDecode(box.get(id) as String?);
    if (record == null) return null;
    try {
      return PlaylistBox.fromEntity(PlaylistEntity.fromJson(record));
    } catch (error) {
      debugPrint('Skipping unreadable playlist record $id: $error');
      return null;
    }
  }

  static String _encodePlaylist(PlaylistBox playlist) {
    return _safeEncode(playlist.toEntity().toJson());
  }

  static bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Settings operations
  static Future<AppSettings> saveSettings(AppSettings settings) {
    return _settingsWrites.run(() => _saveSettingsUnqueued(settings));
  }

  /// Applies [transform] to the latest persisted snapshot inside the same
  /// serialized settings operation, then commits and returns that snapshot.
  static Future<AppSettings> mutateSettings(
    AppSettings Function(AppSettings current) transform,
  ) {
    return _settingsWrites.run(() async {
      final current = _readSettingsUnqueued();
      return _saveSettingsUnqueued(transform(current));
    });
  }

  static AppSettings? _cachedSettings;

  /// Clears the in-memory settings cache. Intended for tests that need a
  /// fresh read from storage between cases.
  static void resetSettingsCache() => _cachedSettings = null;

  static AppSettings getSettings() {
    if (!_initialized) return const AppSettings();
    return _cachedSettings ?? _readSettingsUnqueued();
  }

  static AppSettings _readSettingsUnqueued() {
    final box = settingsBox;
    if (box == null) return const AppSettings();
    final record = _safeDecode(box.get('app_settings') as String?);
    if (record == null) return const AppSettings();
    try {
      final settings = AppSettings.fromJson(record);
      _cachedSettings = settings;
      return settings;
    } catch (error) {
      debugPrint('Settings decode failed ($error) — using defaults');
      return const AppSettings();
    }
  }

  static Future<AppSettings> _saveSettingsUnqueued(AppSettings settings) async {
    if (!_initialized) throw StateError('HiveStorage is not initialized');
    final box = Hive.box<dynamic>(_settingsBoxName);
    await box.put('app_settings', _safeEncode(settings.toJson()));
    await box.flush();
    // Only advertise the snapshot after Hive confirms the write. A failed put
    // can therefore never make runtime code behave as if it were persisted.
    _cachedSettings = settings;
    return settings;
  }

  // Folder operations
  static Future<AppSettings> addManagedFolder(String path) {
    return mutateSettings((settings) {
      if (settings.managedFolders.contains(path)) return settings;
      return settings.copyWith(
        managedFolders: [...settings.managedFolders, path],
      );
    });
  }

  static Future<AppSettings> removeManagedFolder(String path) {
    return mutateSettings(
      (settings) => settings.copyWith(
        managedFolders: settings.managedFolders
            .where((folder) => folder != path)
            .toList(),
      ),
    );
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
