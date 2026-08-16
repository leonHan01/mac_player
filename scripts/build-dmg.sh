#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacVideoPlayer"
DISPLAY_NAME="Mac Video Player"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
VERSION="${APP_VERSION:-1.0}"
DMG_PATH="$ROOT_DIR/build/$APP_NAME-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/build/dmg-staging.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/build-app.sh"

rm -f "$DMG_PATH"
ditto "$APP_DIR" "$STAGING_DIR/$DISPLAY_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_PATH" >/dev/null

echo "Built $DMG_PATH"
