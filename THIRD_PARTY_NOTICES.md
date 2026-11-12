# Third-party notices

## IINA / libmpv runtime

Mac Video Player bundles the runtime distributed with IINA to decode and render local media, including Matroska (`.mkv`) files, directly. The runtime is dynamically loaded from the app bundle and is not used to transcode media.

IINA is licensed under the GNU General Public License, version 3. This app is therefore distributed as GPLv3 and its complete corresponding source must remain available to recipients. IINA and its source are available at:

- https://github.com/iina/iina
- https://github.com/iina/iina/blob/develop/LICENSE
- https://www.gnu.org/licenses/gpl-3.0.html

The IINA runtime contains libmpv, FFmpeg, and their runtime dependencies. libmpv's client API is ISC-licensed, while the bundled mpv core is normally GPLv2-or-later unless built in LGPL mode. The GPLv3 license applied to this application governs its distribution regardless.

The local import script copies the Frameworks directory from an installed IINA app: `scripts/fetch-iina-runtime.sh`.

## Standalone FFmpeg / x264 clip encoder

The app separately bundles an FFmpeg command-line executable in `Contents/MacOS/ffmpeg`
for exporting video clips. This executable is built from FFmpeg 9.0.2 and x264
commit `31e19f92f00c7003fa115047ce50978bc98c3a0d` with GPL components enabled.
Its FFmpeg and x264 libraries are statically linked; it does not load Homebrew
libraries or use the IINA runtime to transcode video.

Corresponding source archives, their SHA-256 checksums and upstream URLs, license
texts, build configuration, and the build recipes are included in
`Contents/Resources/FFmpeg`. The same material lives in `Vendor/FFmpeg` and
`scripts/build-ffmpeg-runtime.py` in this repository. pkgconf 2.3.0 is an ISC-licensed
build tool, built locally during runtime preparation and not linked into FFmpeg.

Upstream projects:

- https://ffmpeg.org/
- https://github.com/FFmpeg/FFmpeg/tree/n9.0.2
- https://code.videolan.org/videolan/x264
- https://github.com/pkgconf/pkgconf
