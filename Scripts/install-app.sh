#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP_PATH="$("$ROOT_DIR/Scripts/build-app.sh" | tail -n 1)"
INSTALLED_APP_PATH="$INSTALL_DIR/Bryan Tools.app"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP_PATH"
ditto "$APP_PATH" "$INSTALLED_APP_PATH"

echo "Installed $INSTALLED_APP_PATH" >&2
printf '%s\n' "$INSTALLED_APP_PATH"
