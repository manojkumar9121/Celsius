# Celsius

A offline-first Flutter music player for Android. Scans your device storage, plays local audio files, and keeps everything in Hive — no cloud, no accounts, no telemetry.

## Features

- **Local library** — scans managed folders, indexes songs via `onMethodCall` content providers and media store queries
- **Background playback** — `audio_service` + `just_audio` with notification controls, lock-screen art, and headset buttons
- **Queue management** — shuffle, repeat modes (off / one / all), drag-to-reorder, add-to-queue, play-next
- **Waveform visualization** — extracted via compute isolate, cached per file, multiple painter styles (bars, line, ribbon, wave, dots, equalizer, blocks, neon, radial)
- **Now Playing themes** — 9 skins (classic, risoZine, paperPress, pocketLcd, concrete, sumi, concreteNoir, sumiNight) plus a custom color picker
- **Lyrics** — reads embedded LRC tags via `flutter_audio_tagger`, client-side LRC parser
- **Home widget** — Android home-screen widget wired through a `MethodChannel` for play/pause/next/prev
- **Settings persistence** — all preferences saved to Hive as JSON; schema versioned with forward migration hooks

## Permissions

- `READ_EXTERNAL_STORAGE` / `READ_MEDIA_AUDIO` — library scan (declared in `AndroidManifest.xml`)
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` — required for background audio
- `POST_NOTIFICATIONS` — Android 13+ media notification (requested at runtime)
- `WAKE_LOCK` — keeps CPU alive during playback

## Architecture

```
lib/
  main.dart              — entrypoint, Hive init, audio_service bootstrap
  app.dart               — go_router config + top-level widget tree
  core/                  — constants, error boundary, shared widgets
  data/
    local_storage/       — Hive boxes (songs, playlists, settings) + JSON schema
  domain/
    entities/            — SongEntity, PlaylistEntity, AppSettings
  presentation/
    providers/           — Riverpod state notifiers (audio player, library, playlists, settings)
    screens/             — Home, Library, Now Playing, Queue, Playlist detail, Stats, Settings
    widgets/             — Waveform viewer, song tile, mini player, action menu
  services/
    background_audio_service.dart  — AudioPlayerHandler (audio_service)
    widget_service.dart            — Android home widget channel
    lyrics_service.dart            — embedded-lyrics cache + LRC parser
    waveform_extractor_service.dart — isolate-based waveform extraction
```

- **State management**: Riverpod (`flutter_riverpod`). Top-level `ProviderContainer` is created in `main.dart` and passed through `UncontrolledProviderScope`.
- **Routing**: `go_router` with deferred-loaded screens (now-playing, queue, lyrics, stats).
- **Audio stack**: `audio_service` bridges to Android media session; `just_audio` handles decoding/sequencing; `audio_handler` lives in the isolate spawned by `audio_service.init()`.

## Building

Requires Flutter 3.44.5 stable / Dart 3.12.2 (pinned in `.metadata`).

```bash
# Analyze
~/flutter/bin/flutter analyze

# Run tests
~/flutter/bin/flutter test

# Build debug APK
~/flutter/bin/flutter build apk --debug

# Build release APK
~/flutter/bin/flutter build apk --release

# Regenerate Hive adapters after editing @HiveType classes
~/flutter/bin/dart run build_runner build
```

Icons are generated, not hand-made. To update them:

```bash
python3 build_icons.py          # Android launcher/splash/notification icons
python3 generate_icons.py       # assets/icons/*.png
```

## Project layout note

This repo contains two nearly identical Flutter projects:

- `celsius/` — active development workspace (has `build/`, `.dart_tool/`)
- `C-clone/` — production copy synced to GitHub

All changes are made in `celsius/` first and then mirrored to `C-clone/`. Run `pub get`, `build_runner`, `analyze`, and `test` in both after mirroring.
