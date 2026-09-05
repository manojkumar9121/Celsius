import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_audio_tagger/flutter_audio_tagger.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:celsuis/data/local_storage/hive_storage.dart';
import 'package:celsuis/data/local_storage/song_box.dart';
import 'package:celsuis/domain/entities/song_entity.dart';
import 'package:permission_handler/permission_handler.dart';

const _channel = MethodChannel('com.celsuis.celsuis/audio_scanner');

/// Durations below this value are suspicious: older builds persisted
/// MediaStore durations in seconds (e.g. 240 for a 4-minute song) instead
/// of milliseconds. Songs with a shorter-than-10s duration are re-measured
/// during scans to repair the corrupted rows.
const int _kSuspiciousDurationMs = 10000;

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier();
});

class LibraryNotifier extends StateNotifier<LibraryState> {
  final FlutterAudioTagger _tagger = FlutterAudioTagger();
  final AudioPlayer _durationPlayer = AudioPlayer();
  bool _artworkExtractionRunning = false;
  Future<void> _scanQueue = Future.value();
  String _selectedAlbum = '';
  String _selectedArtist = '';

  LibraryNotifier() : super(const LibraryState()) {
    _init();
  }

  Future<void> _init() async {
    final settings = HiveStorage.getSettings();
    final managedFolders = settings.managedFolders;
    state = state.copyWith(scannedFolders: managedFolders);
    await loadSongs();
    if (settings.autoScanEnabled && managedFolders.isNotEmpty) {
      await _rescanManagedFolders(managedFolders);
      // Newly found songs are persisted during the rescan; reload so they
      // show up immediately instead of on the next app start.
      if (mounted) {
        state = state.copyWith(
          songs: HiveStorage.getAllSongs().map((box) => box.toEntity()).toList(),
        );
      }
    }
  }

  /// Manual library refresh (pull-to-refresh on the home screen): reloads the
  /// library from storage and rescans every managed folder for new songs.
  /// Unlike the startup auto-scan, this runs even when autoScan is disabled —
  /// a manual refresh is an explicit request to pick up new files.
  Future<void> refreshLibrary() async {
    try {
      state = state.copyWith(
        songs: HiveStorage.getAllSongs().map((box) => box.toEntity()).toList(),
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }

    final settings = HiveStorage.getSettings();
    if (settings.managedFolders.isNotEmpty) {
      await _rescanManagedFolders(settings.managedFolders);
    }

    if (mounted) {
      state = state.copyWith(
        songs: HiveStorage.getAllSongs().map((box) => box.toEntity()).toList(),
      );
    }
  }

  Future<void> _rescanManagedFolders(List<String> folders) async {
    for (final folder in folders) {
      final dir = Directory(folder);
      if (await dir.exists()) {
        try {
          await _scanFolderInternal(folder, showProgress: false);
        } catch (e) {
          debugPrint('Rescan failed for $folder: $e');
        }
      } else {
        try {
          await _pruneMissingSongs(folder);
        } catch (e) {
          debugPrint('Prune failed for $folder: $e');
        }
      }
    }
  }

  Future<void> _extractMissingArtwork() async {
    if (_artworkExtractionRunning) return;
    _artworkExtractionRunning = true;
    try {
      final allSongs = HiveStorage.getAllSongs();
      final missing = allSongs.where((box) =>
          box.coverArtPath == null || box.coverArtPath!.isEmpty ||
          !File(box.coverArtPath!).existsSync()).toList();
      if (missing.isEmpty) return;

      for (final box in missing) {
        try {
          final filePath = box.filePath;
          Uint8List? artwork;

          if (filePath.startsWith('content://')) {
            try {
              final result = await _channel.invokeMethod<Uint8List>('extractArtwork', {'path': filePath});
              artwork = result;
            } catch (e) {
              debugPrint('Native artwork extraction failed for $filePath: $e');
            }
          }

          if (artwork == null || artwork.isEmpty) {
            final taggerPath = (box.realPath != null && box.realPath!.isNotEmpty) ? box.realPath! : filePath;
            try {
              artwork = await _tagger.getArtWork(taggerPath);
            } catch (e) {
              debugPrint('Tagger artwork extraction failed for $taggerPath: $e');
            }
          }

          if (artwork == null || artwork.isEmpty) {
            try {
              final result = await _channel.invokeMethod<Uint8List>('extractArtwork', {'path': filePath});
              artwork = result;
            } catch (e) {
              debugPrint('Fallback native artwork extraction failed for $filePath: $e');
            }
          }

          if (artwork != null && artwork.isNotEmpty) {
            final dir = await getApplicationDocumentsDirectory();
            final coverDir = Directory('${dir.path}/covers');
            if (!await coverDir.exists()) {
              await coverDir.create(recursive: true);
            }
            final ext = _getImageExtension(artwork);
            final coverFile = File('${coverDir.path}/${box.id}$ext');
            await coverFile.writeAsBytes(artwork);
            if (await coverFile.exists() && await coverFile.length() > 0) {
              box.coverArtPath = coverFile.path;
              await HiveStorage.updateSong(box);
            }
          }
        } catch (e) {
          debugPrint('Error extracting artwork for ${box.title}: $e');
        }
      }

      final updatedSongs = HiveStorage.getAllSongs().map((box) => box.toEntity()).toList();
      if (mounted) {
        state = state.copyWith(songs: updatedSongs);
      }
    } finally {
      _artworkExtractionRunning = false;
    }
  }

  String _generateId(String filePath) {
    final bytes = utf8.encode(filePath);
    int hash = 5381;
    for (final byte in bytes) {
      hash = ((hash << 5) + hash) ^ byte;
    }
    return 'song_${hash.abs().toRadixString(36)}';
  }

  Future<void> loadSongs() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final existingSongs = HiveStorage.getAllSongs();
      state = state.copyWith(
        songs: existingSongs.map((box) => box.toEntity()).toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
    await _extractMissingArtwork();
  }

  Future<void> scanFolder(String folderPath) async {
    state = state.copyWith(isScanning: true, scanningProgress: 0.0, error: null);
    try {
      await _scanFolderInternal(folderPath, showProgress: true);
      await HiveStorage.addManagedFolder(folderPath);
      final allSongs = HiveStorage.getAllSongs();
      if (mounted) {
        state = state.copyWith(
          songs: allSongs.map((box) => box.toEntity()).toList(),
          isScanning: false,
          scanningProgress: 1.0,
          scannedFolders: state.scannedFolders.contains(folderPath)
              ? state.scannedFolders
              : [...state.scannedFolders, folderPath],
        );
      }
    } catch (e) {
      debugPrint('Scan failed for $folderPath: $e');
      if (mounted) {
        state = state.copyWith(
          isScanning: false,
          scanningProgress: 0.0,
          error: state.error ?? 'Scan failed: $e',
        );
      }
    }
  }

  Future<void> _scanFolderInternal(String folderPath, {required bool showProgress}) {
    final result = _scanQueue.then((_) => _scanFolderInternalSerialized(folderPath, showProgress: showProgress));
    _scanQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _scanFolderInternalSerialized(String folderPath, {required bool showProgress}) async {
    final audioExtensions = ['.mp3', '.flac', '.ogg', '.aac', '.m4a', '.wav', '.opus'];
    final allFiles = <Map<String, String>>[];

    bool manageStorageGranted = false;

    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted) {
        manageStorageGranted = true;
      } else {
        final status = await Permission.manageExternalStorage.request();
        manageStorageGranted = status.isGranted;
      }
    }

    if (manageStorageGranted) {
      try {
        final dir = Directory(folderPath);
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final ext = audioExtensions.any((e) => entity.path.toLowerCase().endsWith(e));
              if (ext) {
                allFiles.add({'path': entity.path, 'uri': ''});
              }
            }
          }
        } else {
          state = state.copyWith(error: 'Folder not found: $folderPath', isScanning: false);
          await _pruneMissingSongs(folderPath);
          return;
        }
      } catch (e) {
        state = state.copyWith(
          error: 'Cannot access files. Error: $e',
          isScanning: false,
        );
        return;
      }
    } else if (Platform.isAndroid) {
      int? apiLevel;
      try {
        apiLevel = await _channel.invokeMethod<int>('getApiLevel');
      } catch (_) {}
      final status = apiLevel != null && apiLevel >= 33
          ? await Permission.audio.request()
          : await Permission.storage.request();
      if (!status.isGranted) {
        state = state.copyWith(
          error: 'Cannot access audio files. Please grant storage permission in App Settings.',
          isScanning: false,
        );
        return;
      }

      try {
        final result = await _channel.invokeMethod<List<dynamic>>('scanMediaStore');
        if (result != null) {
          for (final entry in result) {
            final map = Map<String, dynamic>.from(entry as Map);
            final path = map['path'] as String? ?? '';
            final realPath = map['realPath'] as String? ?? '';
            final uri = map['uri'] as String? ?? '';
            final title = map['title'] as String? ?? '';
            final artist = map['artist'] as String? ?? '';
            final album = map['album'] as String? ?? '';
            final duration = map['duration'] as int? ?? 0;
            if (path.isNotEmpty || uri.isNotEmpty) {
              allFiles.add({
                'path': path,
                'realPath': realPath,
                'uri': uri,
                'title': title,
                'artist': artist,
                'album': album,
                'duration': duration.toString(),
              });
            }
          }
        }
      } catch (e) {
            debugPrint('MediaStore scan failed: $e');
      }
    }

    if (allFiles.isEmpty) {
      final msg = manageStorageGranted
          ? 'No audio files found in the selected folder.'
          : 'Cannot access audio files. Try granting "All files access" in App Settings.\nGo to Settings → Apps → Celsuis → "Allow management of all files".';
      state = state.copyWith(error: msg, isScanning: false);
      return;
    }

    int processed = 0;
    final total = allFiles.length;

    for (final fileInfo in allFiles) {
      final filePath = fileInfo['path']!;
      final realPath = fileInfo['realPath'] ?? '';
      final id = _generateId(realPath.isNotEmpty ? realPath : filePath);
      final existingBox = HiveStorage.getSong(id);
      if (existingBox == null) {
        final song = await _extractMetadata(
          filePath,
          realPath: fileInfo['realPath'],
          preTitle: fileInfo['title'],
          preArtist: fileInfo['artist'],
          preAlbum: fileInfo['album'],
          preDurationMs: int.tryParse(fileInfo['duration'] ?? '') ?? 0,
        );
        if (song != null) {
          await HiveStorage.addSong(song);
        }
      } else if (existingBox.durationMs > 0 &&
          existingBox.durationMs < _kSuspiciousDurationMs) {
        // Legacy bug: durations were persisted in seconds instead of
        // milliseconds. Re-derive the correct duration for affected songs.
        int corrected = int.tryParse(fileInfo['duration'] ?? '') ?? 0;
        if (corrected == 0) {
          final song = await _extractMetadata(
            filePath,
            realPath: fileInfo['realPath'],
            preTitle: fileInfo['title'],
            preArtist: fileInfo['artist'],
            preAlbum: fileInfo['album'],
          );
          corrected = song?.durationMs ?? 0;
        }
        if (corrected > 0 && corrected != existingBox.durationMs) {
          existingBox.durationMs = corrected;
          await HiveStorage.updateSong(existingBox);
        }
      }
      processed++;
      if (showProgress && mounted) {
        final allSongs = HiveStorage.getAllSongs();
        state = state.copyWith(
          songs: allSongs.map((box) => box.toEntity()).toList(),
          isScanning: true,
          scanningProgress: processed / total,
        );
      }
    }

    await _pruneMissingSongs(folderPath);
  }

  Future<void> _pruneMissingSongs(String folderPath) async {
    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    final removedIds = <String>[];
    for (final song in HiveStorage.getAllSongs()) {
      final inFolder = (song.filePath.isNotEmpty && song.filePath.startsWith(prefix)) ||
          (song.realPath?.isNotEmpty == true && song.realPath!.startsWith(prefix));
      if (!inFolder) continue;
      if (song.filePath.startsWith('content://') &&
          (song.realPath == null || song.realPath!.isEmpty)) {
        continue;
      }
      final fileExists = _fileExists(song.filePath) || _fileExists(song.realPath);
      if (!fileExists) {
        removedIds.add(song.id);
      }
    }
    if (removedIds.isEmpty) return;

    await HiveStorage.deleteSongs(removedIds);
    if (mounted) {
      state = state.copyWith(
        songs: state.songs.where((s) => !removedIds.contains(s.id)).toList(),
      );
    }
    debugPrint('Removed ${removedIds.length} songs with missing files from $folderPath');
  }

  bool _fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    if (path.startsWith('content://')) return false;
    return File(path).existsSync();
  }

  Future<SongBox?> _extractMetadata(
    String filePath, {
    String? realPath,
    String? preTitle,
    String? preArtist,
    String? preAlbum,
    int preDurationMs = 0,
  }) async {
    int durationMs = preDurationMs;
    final taggerPath = (realPath != null && realPath.isNotEmpty) ? realPath : filePath;

    if (durationMs == 0) {
      try {
        if (filePath.startsWith('content://')) {
          await _durationPlayer.setAudioSource(AudioSource.uri(Uri.parse(filePath)));
        } else {
          await _durationPlayer.setFilePath(taggerPath);
        }
        // Wait until the player has finished loading before reading duration.
        // A fixed 300ms delay is unreliable for large files or slow storage;
        // listening to the duration stream guarantees we get a valid value.
        final dur = await _waitForDuration(_durationPlayer);
        if (dur != null && dur.inMilliseconds > 0) {
          durationMs = dur.inMilliseconds;
        }
      } catch (e) {
        debugPrint('Error reading duration from $taggerPath: $e');
      }
    }

    try {
      final idPath = (realPath != null && realPath.isNotEmpty) ? realPath : filePath;
      final id = _generateId(idPath);
      String title;
      String artist;
      String album;
      String? coverArtPath;

      if (preTitle != null && preTitle.isNotEmpty) {
        title = preTitle;
        artist = preArtist ?? 'Unknown Artist';
        album = preAlbum ?? 'Unknown Album';
      } else {
        try {
          final tag = await _tagger.getAllTags(taggerPath);
          if (tag != null && (tag.title?.isNotEmpty == true || tag.artist?.isNotEmpty == true)) {
            title = tag.title?.isNotEmpty == true ? tag.title! : _extractTitleFromFile(filePath);
            artist = tag.artist?.isNotEmpty == true ? tag.artist! : 'Unknown Artist';
            album = tag.album?.isNotEmpty == true ? tag.album! : 'Unknown Album';
          } else {
            throw Exception('Empty tags from tagger');
          }
        } catch (e) {
          debugPrint('Error reading tags via tagger from $taggerPath: $e');
          try {
            final nativeTags = await _channel.invokeMethod<Map>('extractTags', {'path': filePath});
            if (nativeTags != null) {
              final nativeTitle = (nativeTags['title'] as String?)?.trim();
              final nativeArtist = (nativeTags['artist'] as String?)?.trim();
              final nativeAlbum = (nativeTags['album'] as String?)?.trim();
              if (nativeTitle?.isNotEmpty == true) {
                title = nativeTitle!;
              } else {
                title = _extractTitleFromFile(filePath);
              }
              if (nativeArtist?.isNotEmpty == true) {
                artist = nativeArtist!;
              } else {
                artist = 'Unknown Artist';
              }
              if (nativeAlbum?.isNotEmpty == true) {
                album = nativeAlbum!;
              } else {
                album = 'Unknown Album';
              }
              if (durationMs == 0) {
                final nativeDuration = nativeTags['duration'] as String?;
                if (nativeDuration?.isNotEmpty == true) {
                  durationMs = int.tryParse(nativeDuration!) ?? 0;
                }
              }
            } else {
              title = _extractTitleFromFile(filePath);
              artist = 'Unknown Artist';
              album = 'Unknown Album';
            }
          } catch (nativeError) {
            debugPrint('Error reading tags via native from $filePath: $nativeError');
            title = _extractTitleFromFile(filePath);
            artist = 'Unknown Artist';
            album = 'Unknown Album';
          }
        }
      }

      Uint8List? artwork;

      if (filePath.startsWith('content://')) {
        try {
          final result = await _channel.invokeMethod<Uint8List>('extractArtwork', {'path': filePath});
          artwork = result;
        } catch (e) {
          debugPrint('Native artwork extraction failed for $filePath: $e');
        }
      }

      if (artwork == null || artwork.isEmpty) {
        try {
          artwork = await _tagger.getArtWork(taggerPath);
        } catch (e) {
          debugPrint('Error reading cover art from $taggerPath: $e');
        }
      }

      if (artwork == null || artwork.isEmpty) {
        try {
          final result = await _channel.invokeMethod<Uint8List>('extractArtwork', {'path': filePath});
          artwork = result;
        } catch (e) {
          debugPrint('Fallback native artwork extraction failed for $filePath: $e');
        }
      }

      if (artwork != null && artwork.isNotEmpty) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final coverDir = Directory('${dir.path}/covers');
          if (!await coverDir.exists()) {
            await coverDir.create(recursive: true);
          }
          final ext = _getImageExtension(artwork);
          final coverFile = File('${coverDir.path}/$id$ext');
          await coverFile.writeAsBytes(artwork);
          if (await coverFile.exists() && await coverFile.length() > 0) {
            coverArtPath = coverFile.path;
          }
        } catch (e) {
          debugPrint('Error saving cover art: $e');
        }
      }

      return SongBox.fromEntity(SongEntity(
        id: id,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        filePath: filePath,
        realPath: realPath,
        coverArtPath: coverArtPath,
        dateAdded: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Error reading metadata from $taggerPath: $e');
      final idPath = (realPath != null && realPath.isNotEmpty) ? realPath : filePath;
      final id = _generateId(idPath);
      return SongBox.fromEntity(SongEntity(
        id: id,
        title: preTitle ?? _extractTitleFromFile(filePath),
        filePath: filePath,
        realPath: realPath,
        dateAdded: DateTime.now(),
      ));
    }
  }

  String _getImageExtension(List<int> bytes) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return '.png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return '.jpg';
      }
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        return '.webp';
      }
    }
    return '.jpg';
  }

  String _extractTitleFromFile(String filePath) {
    final fileName = filePath.split('/').last;
    return fileName.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll(RegExp(r'[_-]'), ' ');
  }

  void clearLibrary() {
    HiveStorage.clearAllSongs();
    state = state.copyWith(songs: []);
  }

  void removeSong(String songId) {
    HiveStorage.deleteSong(songId);
    state = state.copyWith(songs: state.songs.where((s) => s.id != songId).toList());
  }

  void toggleFavorite(String songId) {
    HiveStorage.toggleFavorite(songId);
    final updatedSongs = state.songs.map((s) {
      if (s.id == songId) return s.copyWith(isFavorite: !s.isFavorite);
      return s;
    }).toList();
    state = state.copyWith(songs: updatedSongs);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void selectAlbum(String album) {
    if (_selectedAlbum == album) {
      _selectedAlbum = '';
    } else {
      _selectedAlbum = album;
      _selectedArtist = '';
    }
    state = state.copyWith(selectedAlbum: _selectedAlbum, selectedArtist: _selectedArtist);
  }

  void selectArtist(String artist) {
    if (_selectedArtist == artist) {
      _selectedArtist = '';
    } else {
      _selectedArtist = artist;
      _selectedAlbum = '';
    }
    state = state.copyWith(selectedAlbum: _selectedAlbum, selectedArtist: _selectedArtist);
  }

  List<SongEntity> get filteredSongs {
    var songs = state.songs;

    if (state.searchQuery.isNotEmpty) {
      final query = state.searchQuery.toLowerCase();
      songs = songs.where((s) =>
          s.title.toLowerCase().contains(query) ||
          s.artist.toLowerCase().contains(query) ||
          s.album.toLowerCase().contains(query)).toList();
    }

    if (_selectedAlbum.isNotEmpty) {
      songs = songs.where((s) => s.album == _selectedAlbum).toList();
    }

    if (_selectedArtist.isNotEmpty) {
      songs = songs.where((s) => s.artist == _selectedArtist).toList();
    }

    return songs;
  }

  List<String> get albums {
    final querySongs = state.searchQuery.isEmpty
        ? state.songs
        : state.songs.where((s) =>
            s.title.toLowerCase().contains(state.searchQuery.toLowerCase()) ||
            s.artist.toLowerCase().contains(state.searchQuery.toLowerCase()) ||
            s.album.toLowerCase().contains(state.searchQuery.toLowerCase())).toList();
    final albumSet = querySongs.map((s) => s.album).toSet();
    return albumSet.toList()..sort();
  }

  List<String> get artists {
    final querySongs = state.searchQuery.isEmpty
        ? state.songs
        : state.songs.where((s) =>
            s.title.toLowerCase().contains(state.searchQuery.toLowerCase()) ||
            s.artist.toLowerCase().contains(state.searchQuery.toLowerCase()) ||
            s.album.toLowerCase().contains(state.searchQuery.toLowerCase())).toList();
    final artistSet = querySongs.map((s) => s.artist).toSet();
    return artistSet.toList()..sort();
  }

  Map<String, List<SongEntity>> get songsByAlbum {
    final grouped = <String, List<SongEntity>>{};
    for (final song in filteredSongs) {
      grouped.putIfAbsent(song.album, () => []).add(song);
    }
    return grouped;
  }

  Map<String, List<SongEntity>> get songsByArtist {
    final grouped = <String, List<SongEntity>>{};
    for (final song in filteredSongs) {
      grouped.putIfAbsent(song.artist, () => []).add(song);
    }
    return grouped;
  }

  /// Waits for the player to report a non-zero duration, with a 10s timeout.
  /// Returns null if the duration is not available within the timeout.
  Future<Duration?> _waitForDuration(AudioPlayer player, {Duration timeout = const Duration(seconds: 10)}) async {
    Completer<Duration?> completer = Completer<Duration?>();
    final sub = player.durationStream.listen((dur) {
      if (dur != null && dur.inMilliseconds > 0 && !completer.isCompleted) {
        completer.complete(dur);
      }
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.complete(null);
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  @override
  void dispose() {
    _durationPlayer.dispose();
    super.dispose();
  }
}

class LibraryState {
  final List<SongEntity> songs;
  final bool isLoading;
  final bool isScanning;
  final double scanningProgress;
  final List<String> scannedFolders;
  final String? error;
  final String searchQuery;
  final String selectedAlbum;
  final String selectedArtist;

  const LibraryState({
    this.songs = const [],
    this.isLoading = false,
    this.isScanning = false,
    this.scanningProgress = 0.0,
    this.scannedFolders = const [],
    this.error,
    this.searchQuery = '',
    this.selectedAlbum = '',
    this.selectedArtist = '',
  });

  LibraryState copyWith({
    List<SongEntity>? songs,
    bool? isLoading,
    bool? isScanning,
    double? scanningProgress,
    List<String>? scannedFolders,
    String? error,
    String? searchQuery,
    String? selectedAlbum,
    String? selectedArtist,
  }) {
    return LibraryState(
      songs: songs ?? this.songs,
      isLoading: isLoading ?? this.isLoading,
      isScanning: isScanning ?? this.isScanning,
      scanningProgress: scanningProgress ?? this.scanningProgress,
      scannedFolders: scannedFolders ?? this.scannedFolders,
      error: error ?? this.error,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedAlbum: selectedAlbum ?? this.selectedAlbum,
      selectedArtist: selectedArtist ?? this.selectedArtist,
    );
  }
}
