# Mac Video Player

A small macOS video player for local video files.

## Features

- Open a local MP4, MOV, M4V, or MKV file and automatically build a playlist from the same folder.
- Open a folder and play supported videos by filename or by file size.
- View the current playlist in a right-side panel and click an item to play it.
- Control playback from the bottom bar: previous, play/pause, next, playback mode, timeline, and volume.
- Add local tags to videos for categorization and filter folder playback by tag.
- Move the current video to the Trash with Delete after confirmation.
- Press Space to play or pause, and reveal the current file in Finder from the File menu.
- Drag a video file into the window to play it.
- View the app version, build number, and build creation time from `Mac Video Player > About Mac Video Player`.
- IINA/libmpv decoding, hardware acceleration, and GPU rendering for every supported format.
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

The debug executable does not contain the bundled IINA/libmpv runtime, so use the packaged app when testing playback.

For fast app testing during development, use:

```sh
./script/build_and_run.sh
```

The Codex Run action is also wired to this script. It rebuilds the app bundle, stops any running copy, and opens the latest build.

## Supported formats

MP4, MOV, M4V, and MKV files all play directly through the bundled IINA/libmpv runtime. The original file is decoded and rendered in place, with no remuxing or transcoding step. libmpv uses FFmpeg's demuxers/decoders, VideoToolbox hardware decoding where the Mac supports the codec, and a GPU render context modeled on IINA's playback architecture.

The bundled IINA runtime includes libmpv and its FFmpeg dependencies. It supports the common Matroska codec combinations and adds roughly 100 MB to the app bundle. To import the runtime from an installed official IINA app when `Vendor/IINAFrameworks` is not present:

```sh
./scripts/fetch-iina-runtime.sh
```

This project is a GPLv3 work because it distributes the IINA/libmpv runtime. Keep the complete corresponding source code available whenever distributing a build. See `THIRD_PARTY_NOTICES.md` for attribution and license links.

The reviewed upstream source is retained at `ThirdParty/IINA` (commit `db549a6`); the root `LICENSE` contains the GPLv3 text.

## Folder playback

Choose `File > Open...`, double-click a video, or drag a video into the window to play it. The app scans that video's folder for MP4, MOV, M4V, and MKV files and adds them to the playlist, starting from the video you opened.

Choose `File > Open Folder...` or use the `Open Folder...` button to scan the selected folder directly. The app automatically starts the next video when the current one finishes.

Folder scanning runs in the background, so large folders can build the playlist without freezing the player window.

The playlist appears on the right side of the player. Click any row to switch directly to that video.

Use `Sort: Name` / `Sort: Size` in the tag bar, or choose `File > Toggle Size Sort`, to switch between filename sorting and file-size sorting. Size sorting plays larger files first.

Use the bottom playback bar to switch previous/next videos, play or pause, seek through the current video, and adjust or mute volume. You can also choose `File > Previous Video` and `File > Next Video`.

Scroll up over the volume slider to increase volume, or scroll down to decrease it.

Press Space to play or pause. The window title shows the current video name and playlist position.

Press the Up Arrow key to switch to the previous video, or the Down Arrow key to switch to the next video.

Press the Right Arrow key to jump forward 5 seconds, or the Left Arrow key to jump backward 5 seconds.

Scroll down over the video area to switch to the next video, or scroll up to switch to the previous video. Mouse-wheel events are captured at the window level so AVKit's internal video view cannot consume them. The playlist panel keeps normal scrolling.

Use the `Order` / `Shuffle` button to switch between sequential playback and random playback. In shuffle mode, automatic next and the Next button pick a random different video; Previous returns through the shuffle history.

Use the tag bar below the video to see the current video's tags. Click the `×` on a tag to remove it, or type a new tag in `Add tag` and press Return; existing tags appear as suggestions. Use `Filter: All` to filter the current folder playback by tag. Choose `File > Edit Tags...` or press Command-T to edit the full tag list for the current video. Tags are saved locally in `~/Library/Application Support/MacVideoPlayer/tags.json` and the original video file is not modified.

Press Delete or choose `File > Delete Current Video` to move the current video to the Trash. The app asks for confirmation before deleting.

Choose `File > Reveal in Finder` to locate the current video file.
