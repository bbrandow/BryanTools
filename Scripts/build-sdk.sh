#!/usr/bin/env bash
# Sourced by build/test/update scripts; exports a validated SDKROOT without changing xcode-select.

bryan_tools_resolve_sdk() (
    set -euo pipefail
    local script_dir preferred sdk_dir candidate version visited duplicate
    local explicit_sdk="${SDKROOT:-}"
    local probe_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/BryanToolsSDK.XXXXXX")"
    trap 'rm -rf "$probe_dir"' EXIT

    if ! command -v swiftc >/dev/null 2>&1; then
        echo "Swift compiler not found. Install Xcode or the macOS Command Line Tools." >&2
        return 1
    fi

    if [[ -n "$explicit_sdk" ]]; then
        preferred="$explicit_sdk"
    else
        if ! preferred="$(xcrun --sdk macosx --show-sdk-path 2>"$probe_dir/discovery.log")"; then
            echo "Unable to locate the selected macOS SDK. Install or select a complete Xcode/Command Line Tools installation." >&2
            cat "$probe_dir/discovery.log" >&2
            return 1
        fi
    fi
    if [[ ! -d "$preferred" ]]; then
        echo "macOS SDK directory does not exist: $preferred" >&2
        echo "Set SDKROOT to an installed .sdk directory, or unset SDKROOT to use automatic selection." >&2
        return 1
    fi
    preferred="$(cd "$preferred" && pwd -P)"

    bryan_tools_probe_sdk() {
        swiftc -typecheck -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
            -sdk "$1" "$script_dir/SwiftUIBuildProbe.swift" >"$probe_dir/probe.log" 2>&1
    }

    if bryan_tools_probe_sdk "$preferred"; then
        echo "Using macOS SDK: $preferred" >&2
        printf '%s\n' "$preferred"
        return 0
    fi
    cp "$probe_dir/probe.log" "$probe_dir/preferred.log"
    if [[ -n "$explicit_sdk" ]]; then
        echo "The SDK explicitly selected by SDKROOT cannot compile SwiftUI: $preferred" >&2
        cat "$probe_dir/preferred.log" >&2
        echo "Unset SDKROOT to try other installed SDKs, or select a complete compatible SDK." >&2
        return 1
    fi

    echo "The default macOS SDK failed the SwiftUI compile check: $preferred" >&2
    echo "Checking other SDKs in the selected developer-tools installation..." >&2
    sdk_dir="$(dirname "$preferred")"
    local seen=("$preferred")
    while IFS= read -r version; do
        candidate="$(cd "$sdk_dir/MacOSX${version}.sdk" && pwd -P)"
        duplicate=false
        for visited in "${seen[@]}"; do
            if [[ "$visited" == "$candidate" ]]; then duplicate=true; break; fi
        done
        if [[ "$duplicate" == true ]]; then continue; fi
        seen+=("$candidate")
        if bryan_tools_probe_sdk "$candidate"; then
            echo "Using compatible fallback macOS SDK: $candidate" >&2
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(
        for candidate in "$sdk_dir"/MacOSX[0-9]*.sdk; do
            [[ -d "$candidate" && ! -L "$candidate" ]] || continue
            version="${candidate##*/MacOSX}"
            version="${version%.sdk}"
            if [[ "$version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then printf '%s\n' "$version"; fi
        done | sort -t . -k1,1nr -k2,2nr -k3,3nr
    )

    echo "No compatible macOS SDK was found. The default SDK's compiler diagnostic was:" >&2
    cat "$probe_dir/preferred.log" >&2
    echo "Install a complete compatible Xcode or Command Line Tools release, or set SDKROOT to a compatible installed SDK." >&2
    echo "Bryan Tools has not been stopped or replaced by this SDK check." >&2
    return 1
)

bryan_tools_configure_sdk() {
    local selected_sdk
    selected_sdk="$(bryan_tools_resolve_sdk)" || return 1
    export SDKROOT="$selected_sdk"
}

bryan_tools_configure_sdk
