#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IINA_APP="${IINA_APP:-/Applications/IINA.app}"
SOURCE_DIR="$IINA_APP/Contents/Frameworks"
DESTINATION_DIR="$ROOT_DIR/Vendor/IINAFrameworks"

if [[ ! -f "$SOURCE_DIR/libmpv.2.dylib" ]]; then
    echo "IINA's libmpv runtime was not found at $SOURCE_DIR." >&2
    echo "Install the official IINA app first, or set IINA_APP to its .app path." >&2
    exit 1
fi

if [[ -e "$DESTINATION_DIR" ]]; then
    echo "Refusing to overwrite $DESTINATION_DIR. Remove it manually before importing another IINA runtime." >&2
    exit 1
fi

mkdir -p "$ROOT_DIR/Vendor"
ditto "$SOURCE_DIR" "$DESTINATION_DIR"
echo "Imported IINA/libmpv runtime to $DESTINATION_DIR"
