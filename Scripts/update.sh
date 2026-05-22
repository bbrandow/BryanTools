#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
LAUNCH_APP="${LAUNCH_APP:-1}"

cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a Git working tree: $ROOT_DIR" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Refusing to update because the working tree has local changes:" >&2
    git status --short >&2
    echo "Commit, stash, or remove those changes before running this script." >&2
    exit 1
fi

echo "Pulling latest changes..."
git pull --ff-only

echo "Running self-tests..."
"$ROOT_DIR/Scripts/test.sh"

echo "Stopping any running Bryan Tools instance..."
pkill -x BryanTools >/dev/null 2>&1 || true

echo "Installing $CONFIGURATION build..."
APP_PATH="$(CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/Scripts/install-app.sh" | tail -n 1)"

case "$LAUNCH_APP" in
    1|true|TRUE|yes|YES)
        echo "Launching $APP_PATH..."
        open "$APP_PATH"
        ;;
esac

echo "Bryan Tools is up to date."
