# Third-party notices

## IINA / libmpv runtime

Mac Video Player bundles the runtime distributed with IINA to decode and render local media, including Matroska (`.mkv`) files, directly. The runtime is dynamically loaded from the app bundle and is not used to transcode media.

IINA is licensed under the GNU General Public License, version 3. This app is therefore distributed as GPLv3 and its complete corresponding source must remain available to recipients. IINA and its source are available at:

- https://github.com/iina/iina
- https://github.com/iina/iina/blob/develop/LICENSE
- https://www.gnu.org/licenses/gpl-3.0.html

The IINA runtime contains libmpv, FFmpeg, and their runtime dependencies. libmpv's client API is ISC-licensed, while the bundled mpv core is normally GPLv2-or-later unless built in LGPL mode. The GPLv3 license applied to this application governs its distribution regardless.

The local import script copies the Frameworks directory from an installed IINA app: `scripts/fetch-iina-runtime.sh`.
