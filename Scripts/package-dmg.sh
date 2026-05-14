#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
DMG_PATH="$DIST_DIR/BryanTools-$VERSION.dmg"

APP_PATH="$(CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/build-app.sh" | tail -n 1)"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

ditto "$APP_PATH" "$STAGING_DIR/Bryan Tools.app"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/Bryan Tools.app"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "Bryan Tools $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"

echo "Packaged $DMG_PATH" >&2
printf '%s\n' "$DMG_PATH"
