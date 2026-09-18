#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/BryanToolsSDKTests.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
SDK_DIR="$FIXTURE/SDKs with spaces"
mkdir -p "$SDK_DIR/MacOSX27.0.sdk" "$SDK_DIR/MacOSX26.5.sdk" "$SDK_DIR/MacOSX26.1.sdk"
SDK_DIR="$(cd "$SDK_DIR" && pwd -P)"
ln -s MacOSX27.0.sdk "$SDK_DIR/MacOSX.sdk"
ln -s MacOSX26.5.sdk "$SDK_DIR/MacOSX26.sdk"

# Fake only the compiler and SDK discovery; exercise the production selection script.
xcrun() { printf '%s\n' "$SDK_DIR/MacOSX.sdk"; }
swiftc() {
    local sdk=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == -sdk ]]; then sdk="$2"; shift; fi
        shift
    done
    printf '%s\n' "$sdk" >>"$FIXTURE/probes.log"
    case "$ACCEPTED_SDKS" in
        *"|$(basename "$sdk")|"*) return 0 ;;
    esac
    echo "error: plugin for module 'SwiftUIMacros' not found" >&2
    return 1
}

select_sdk() (
    unset SDKROOT
    if [[ -n "${1:-}" ]]; then export SDKROOT="$1"; fi
    source "$SCRIPT_DIR/build-sdk.sh" || return 1
    printf '%s\n' "$SDKROOT"
)

expect_sdk() {
    local actual
    actual="$(select_sdk "${2:-}" 2>"$FIXTURE/diagnostic.log")"
    [[ "$actual" == "$SDK_DIR/$1" ]] || {
        echo "FAIL expected $1, got $actual" >&2
        exit 1
    }
}

ACCEPTED_SDKS='|MacOSX27.0.sdk|MacOSX26.5.sdk|MacOSX26.1.sdk|'
expect_sdk MacOSX27.0.sdk
echo "PASS SDK selection prefers a working default"

ACCEPTED_SDKS='|MacOSX26.5.sdk|MacOSX26.1.sdk|'
expect_sdk MacOSX26.5.sdk
echo "PASS SDK selection falls back to the newest compatible installed SDK"

ACCEPTED_SDKS='|MacOSX26.1.sdk|'
expect_sdk MacOSX26.1.sdk
echo "PASS SDK selection tries older compatible SDKs"

ACCEPTED_SDKS='|MacOSX27.0.sdk|MacOSX26.5.sdk|MacOSX26.1.sdk|'
expect_sdk MacOSX26.1.sdk "$SDK_DIR/MacOSX26.1.sdk"
echo "PASS SDK selection respects an explicit SDKROOT"

ACCEPTED_SDKS='|MacOSX26.5.sdk|'
if select_sdk "$SDK_DIR/MacOSX27.0.sdk" >"$FIXTURE/result" 2>"$FIXTURE/diagnostic.log"; then
    echo "FAIL broken explicit SDKROOT must not be silently overridden" >&2; exit 1
fi
grep -q 'explicitly selected' "$FIXTURE/diagnostic.log"
echo "PASS SDK selection reports a broken explicit SDKROOT"

ACCEPTED_SDKS='||'
: >"$FIXTURE/probes.log"
if select_sdk >"$FIXTURE/result" 2>"$FIXTURE/diagnostic.log"; then
    echo "FAIL missing compatible SDK must fail preflight" >&2; exit 1
fi
grep -q 'No compatible macOS SDK' "$FIXTURE/diagnostic.log"
[[ "$(wc -l <"$FIXTURE/probes.log" | tr -d ' ')" == 3 ]]
echo "PASS SDK selection reports no compatible SDK and avoids duplicate alias probes"

if select_sdk "$SDK_DIR/missing.sdk" >"$FIXTURE/result" 2>"$FIXTURE/diagnostic.log"; then
    echo "FAIL missing explicit SDK must fail preflight" >&2; exit 1
fi
grep -q 'does not exist' "$FIXTURE/diagnostic.log"
echo "PASS SDK selection reports a missing explicit SDKROOT"

mkdir -p "$FIXTURE/project/Scripts"
cp "$SCRIPT_DIR/update.sh" "$SCRIPT_DIR/build-sdk.sh" "$SCRIPT_DIR/SwiftUIBuildProbe.swift" "$FIXTURE/project/Scripts/"
if (
    unset SDKROOT
    export SDK_DIR FIXTURE ACCEPTED_SDKS
    git() { return 0; }
    pkill() { : >"$FIXTURE/stopped-app"; }
    export -f xcrun swiftc git pkill
    bash "$FIXTURE/project/Scripts/update.sh"
) >"$FIXTURE/update.log" 2>&1; then
    echo "FAIL updater must stop when no SDK passes preflight" >&2; exit 1
fi
grep -q 'No compatible macOS SDK' "$FIXTURE/update.log"
[[ ! -e "$FIXTURE/stopped-app" ]]
echo "PASS updater rejects an incompatible toolchain before stopping the app"
