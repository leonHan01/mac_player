# Mac Video Player

> A lightweight native macOS video player for watching and organizing local videos with playlists, tags, shuffle playback, and GPU-accelerated IINA/libmpv rendering.

[English](README.md) · [简体中文](README.zh-CN.md)

Mac Video Player is a small native macOS video player focused on a simple local playback workflow. It opens a video or folder, builds a playlist from nearby files, and keeps local tags without modifying the original media.

## Features

- Open local MP4, MOV, M4V, and MKV files.
- Open a folder and build a playlist automatically.
- Sort playlists by filename or file size.
- Play videos sequentially or in shuffle mode, with shuffle history for the Previous action.
- Control playback with play/pause, previous, next, seek, timeline, and volume controls.
- Drag a video file into the window to play it.
- Add, remove, and filter local tags. Tags are stored in a JSON file and do not modify the video files.
- Capture screenshots from the current video with a configurable keyboard shortcut.
- Move the current video to the macOS Trash after confirmation.
- Reveal the current video in Finder.
- Use IINA/libmpv for broad format support, hardware decoding, and GPU rendering.
- Build with Swift Package Manager without an Xcode project.

## Requirements

- macOS 13.0 or later.
- Swift 6 toolchain and the macOS Command Line Tools.
- A bundled IINA/libmpv runtime in `Vendor/IINAFrameworks`.

The repository may already contain the runtime. If it is not present, install the official IINA application and import its Frameworks directory:

```sh
./scripts/fetch-iina-runtime.sh
```

You can set `IINA_APP` when IINA is installed somewhere other than `/Applications/IINA.app`:

```sh
IINA_APP="/path/to/IINA.app" ./scripts/fetch-iina-runtime.sh
```

## Build

Build the application bundle with:

```sh
./scripts/build-app.sh
```

The result is created at:

```text
build/MacVideoPlayer.app
```

To create a DMG installer:

```sh
./scripts/build-dmg.sh
```

To run the Swift executable directly:

```sh
swift run MacVideoPlayer
```

The debug executable does not contain the bundled IINA/libmpv runtime. For playback, use the packaged application built by `scripts/build-app.sh`.

## Tests

Run the test suite with:

```sh
swift test
```

If the toolchain has no XCTest (for example, Command Line Tools without Xcode), run the core regression checks with Python 3:

```sh
python3 scripts/test-regressions.py
```

These checks use temporary fixtures and a fake libmpv client. They cover tag storage, playlist filtering and sorting, playback events, asynchronous commands, screenshots, and clean DMG staging without opening a player window or decoding media. Real playback and DMG creation still require separate integration checks.

## Playback and controls

- `File > Open...` opens a video and scans its folder for supported videos.
- `File > Open Folder...` scans a selected folder directly.
- `File > Previous Video` and `File > Next Video` navigate the playlist.
- `File > Toggle Size Sort` switches between filename and file-size sorting.
- `File > Edit Tags...` edits all tags for the current video.
- `File > Reveal in Finder` opens the current video's location in Finder.
- `File > Delete Current Video` moves the current video to the Trash after confirmation.
- `Space` toggles play/pause.
- `Up Arrow` and `Down Arrow` select the previous or next video.
- `Left Arrow` and `Right Arrow` seek backward or forward by five seconds.
- Scrolling over the video switches to the previous or next video; the playlist panel keeps normal scrolling.
- Scrolling over the volume slider adjusts the volume.

Tags are stored at:

```text
~/Library/Application Support/MacVideoPlayer/tags.json
```

## Runtime and licensing

The application bundles the IINA/libmpv runtime and related media dependencies. The runtime uses FFmpeg and supports hardware decoding where available. Playback decodes the original file directly; it does not remux or transcode the media.

Because the distributed application includes the IINA/libmpv runtime, this project is distributed under the GNU General Public License v3.0. When redistributing a build, keep the complete corresponding source code and third-party notices available to recipients.

See:

- [LICENSE](LICENSE)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- The upstream IINA source reference at `ThirdParty/IINA` (commit `db549a6`)

## Project status

This is a small macOS project intended for local playback and experimentation. The application is not affiliated with or endorsed by IINA, FFmpeg, VLC, Sparkle, or Apple.
