# Mac Video Player

A small macOS video player for local video files.

## Features

- Open local MP4, MOV, and M4V files.
- Open a folder and play supported videos in filename order.
- Control playback from the bottom bar: previous, play/pause, next, playback mode, timeline, and volume.
- Add local tags to videos for categorization.
- Move the current video to the Trash with Delete after confirmation.
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

## Folder playback

Choose `File > Open Folder...` or use the `Open Folder...` button. The app scans the selected folder for MP4, MOV, and M4V files, sorts them by filename, and automatically starts the next video when the current one finishes.

Use the bottom playback bar to switch previous/next videos, play or pause, seek through the current video, and adjust or mute volume. You can also choose `File > Previous Video` and `File > Next Video`.

Press the Up Arrow key to switch to the previous video, or the Down Arrow key to switch to the next video.

Press the Right Arrow key to jump forward 5 seconds, or the Left Arrow key to jump backward 5 seconds.

Use the `Order` / `Shuffle` button to switch between sequential playback and random playback. In shuffle mode, automatic next and the Next button pick a random different video; Previous returns through the shuffle history.

Choose `File > Edit Tags...` or press Command-T to edit tags for the current video. Tags are saved locally in `~/Library/Application Support/MacVideoPlayer/tags.json` and the original video file is not modified.

Press Delete or choose `File > Delete Current Video` to move the current video to the Trash. The app asks for confirmation before deleting.
