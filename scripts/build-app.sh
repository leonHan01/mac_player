#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacVideoPlayer"
APP_VERSION="${APP_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/播放器.png"
ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
IINA_RUNTIME_DIR="${IINA_RUNTIME_DIR:-$ROOT_DIR/Vendor/IINAFrameworks}"
THIRD_PARTY_NOTICES="$ROOT_DIR/THIRD_PARTY_NOTICES.md"
LICENSE_FILE="$ROOT_DIR/LICENSE"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
rm -rf "$ROOT_DIR/.build/module-cache"
swift build \
    --disable-sandbox \
    --cache-path "$ROOT_DIR/.build/swiftpm-cache" \
    -Xcc "-fmodules-cache-path=$ROOT_DIR/.build/module-cache" \
    -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CONTENTS_DIR/Frameworks"
cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon: $ICON_SOURCE" >&2
    exit 1
fi

if [[ ! -f "$IINA_RUNTIME_DIR/libmpv.2.dylib" ]]; then
    echo "Missing bundled IINA/libmpv runtime. Run scripts/fetch-iina-runtime.sh first." >&2
    exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
if ! iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE" >/dev/null 2>&1; then
    python3 "$ROOT_DIR/scripts/make-icns.py" "$ICONSET_DIR" "$ICON_FILE"
fi
ditto "$IINA_RUNTIME_DIR" "$CONTENTS_DIR/Frameworks"
cp "$THIRD_PARTY_NOTICES" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
cp "$LICENSE_FILE" "$RESOURCES_DIR/LICENSE"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.mac-video-player</string>
    <key>CFBundleName</key>
    <string>Mac Video Player</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Video Player</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>MVPBuildDate</key>
    <string>$BUILD_DATE</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>local.mac-video-player.mkv</string>
            <key>UTTypeDescription</key>
            <string>Matroska Video</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.movie</string>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>mkv</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Video Files</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mp4</string>
                <string>m4v</string>
                <string>mov</string>
                <string>mkv</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.mpeg-4</string>
                <string>public.movie</string>
                <string>local.mac-video-player.mkv</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "Built $APP_DIR"
