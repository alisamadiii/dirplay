# Dirplay

A free, open-source, ad-free music & video player for iOS. No accounts, no tracking, no database — **the filesystem is the library**.

## How it works

1. In the Files app, create a folder anywhere (any name, any location — On My iPhone, iCloud Drive, even SMB shares).
2. Inside it, create two folders: `Music` and `Video`.
3. Open Dirplay and pick that folder.

Dirplay mirrors your folder structure **exactly**. Subfolders inside `Music` become browsable folders in the Music tab — nothing is ever merged or flattened. You organize your library in Files; Dirplay just plays it.

## Features

- **Music tab** — browse your folder tree, tap a track to play
- **Spotify-style Now Playing sheet** — large artwork, scrub slider, transport controls
- **Background playback** — lock screen & Control Center controls, AirPods support
- **Queue = current folder** — auto-advances, loops back to the first track after the last
- **Shuffle, repeat-one, playback speed** (0.5×–2×)
- **Video tab** — same folder mirroring, plays with the system player (minimal in v1)
- **Metadata from your files** — ID3/MP4 titles, artists, and embedded artwork

## Privacy

Dirplay stores exactly one thing: a security-scoped bookmark to the folder you picked (in `UserDefaults`). No database, no analytics, no network access. Your files never leave your device.

## Requirements

- iOS 17.0+
- Xcode 16+

## Building

```sh
open Dirplay.xcodeproj
```

Build and run the `Dirplay` scheme. Pure SwiftUI, zero third-party dependencies.

## Supported formats

- **Audio:** mp3, m4a, m4b, aac, wav, flac, aif/aiff, caf
- **Video:** mp4, mov, m4v

## License

MIT
