#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_DIR="$ROOT_DIR/.build"
APP_PATH="$BUILD_DIR/Bryan Tools.app"
BINARY_PATH="$BUILD_DIR/$CONFIGURATION/BryanTools"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/BryanTools"
chmod +x "$APP_PATH/Contents/MacOS/BryanTools"

if command -v codesign >/dev/null 2>&1; then
    codesign \
        --force \
        --sign - \
        --requirements '=designated => identifier "com.local.BryanTools"' \
        "$APP_PATH" >/dev/null 2>&1 || true
fi

echo "Built $APP_PATH" >&2
printf '%s\n' "$APP_PATH"
