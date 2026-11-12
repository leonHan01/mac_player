# Standalone FFmpeg for clip export

This runtime is built from the exact FFmpeg and x264 sources pinned by SHA-256 in
`sources.json`, targeting macOS 13.0. x264 and the FFmpeg libraries are linked
statically. Only macOS system libraries remain dynamically linked. No Homebrew,
network access, or package manager is needed to run the packaged encoder.

`build-info.json` records the built CPU architecture and configuration. The
runtime must cover every CPU architecture in the player executable; the packaging
script rejects a mismatch, a deployment target newer than macOS 13, external
dynamic libraries, missing H.264/AAC encoders, or changed source/binary hashes.
The current application build is for Apple Silicon (arm64).

Rebuild from a repository checkout with the macOS Command Line Tools and Python 3:

```sh
python3 scripts/build-ffmpeg-runtime.py --jobs 4
```

The build compiles its own pkgconf as a build tool, uses project-local staging,
and does not install anything into the system. `--resume` reuses a previous
build's objects after an interrupted build. `build-info.json`'s `binarySHA256`
describes the vendor executable before the app's final signing step.

Applications include these archives, license texts, metadata, and build recipes
under `Contents/Resources/FFmpeg`. To rebuild using only that supplied source
package, copy it into a working directory with this layout:

```sh
mkdir -p workspace/Vendor/FFmpeg workspace/scripts
cp -R "/path/to/MacVideoPlayer.app/Contents/Resources/FFmpeg/" workspace/Vendor/FFmpeg/
cp workspace/Vendor/FFmpeg/Build/*.py workspace/scripts/
cd workspace
python3 scripts/build-ffmpeg-runtime.py --jobs 4
```

FFmpeg is configured with GPL components including x264. See `Licenses` and the
source archives for the applicable GPL terms. pkgconf is an ISC-licensed build
tool and is not linked into the runtime. The macOS SDK and system libraries are
provided by Apple and are not included in this source package.
