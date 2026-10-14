#!/usr/bin/env bash
#
# Builds a drag-to-install DMG for Forex Market Hours.
# Usage: Scripts/make-dmg.sh [version]   (expects build/ForexMarketHours.app; run `make app` first)
set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/build/ForexMarketHours.app"
STAGE="$ROOT_DIR/dmg-root"
DIST="$ROOT_DIR/dist"
DMG="$DIST/ForexMarketHours-$VERSION-macOS.dmg"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP missing — run 'make app' first" >&2
    exit 1
fi

rm -rf "$STAGE" "$DIST"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT_DIR/LICENSE" "$STAGE/LICENSE.txt"

rm -f "$DMG"
hdiutil create -volname "Forex Market Hours" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> DMG: $DMG"
shasum -a 256 "$DMG"
