# Mac Video Player

A small macOS video player for local video files.

## Features

- Open local MP4, MOV, and M4V files.
- Drag a video file into the window to play it.
- Native macOS playback controls through AVKit.
- Builds without an Xcode project.

## Build

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

The application bundle is created at:

```text
build/MacVideoPlayer.app
```

You can also run the debug executable directly:

```sh
swift run MacVideoPlayer
```

## Supported formats

The app uses AVFoundation/AVKit, so MP4, MOV, and M4V playback is native.
