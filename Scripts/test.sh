#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash "$ROOT_DIR/Scripts/test-build-sdk.sh"
source "$ROOT_DIR/Scripts/build-sdk.sh"
swift run --sdk "$SDKROOT" BryanToolsSelfTests
