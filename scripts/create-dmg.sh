#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacVideoPlayer"
VOLUME_NAME="Mac Video Player"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
DMG_PATH="$DMG_DIR/$APP_NAME.dmg"

if [[ ! -d "$APP_DIR" ]]; then
    "$ROOT_DIR/scripts/build-app.sh"
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DMG_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Built $DMG_PATH"
