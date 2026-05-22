# Bryan Tools

Bryan Tools is a local macOS menu bar app for personal productivity tools. The
included tools are Clipboard History, which absorbs the old ClipMan app,
ColorPicker, MacroText, QuickTask, and ShotFloat.

## Build

```sh
swift build
```

## Build an app bundle

```sh
Scripts/build-app.sh
```

The generated app bundle is written to `.build/Bryan Tools.app`.

## Run

```sh
Scripts/run-app.sh
```

Bryan Tools runs as a menu bar app. Press `Shift+Command+V` to open Clipboard
History, `Shift+Option+Command+V` to paste the current clipboard as plain text,
`Shift+Command+~` to pick a screen color, `Shift+Command+/` to configure
MacroText replacements, and `Command+Space` to open QuickTask. If
`Command+Space` cannot be registered, QuickTask falls back to `Option+Space`.
Press `Shift+Command+2` to capture a floating screenshot with ShotFloat.

## Install Locally

```sh
Scripts/install-app.sh
```

The local install copies Bryan Tools to `/Applications/Bryan Tools.app`.
Automatic paste requires macOS Accessibility permission for Bryan Tools.

## Package a DMG

```sh
Scripts/package-dmg.sh
```

The DMG is written to `dist/BryanTools-0.1.0.dmg`. It contains
`Bryan Tools.app` and an `/Applications` shortcut. This build is ad-hoc signed
for personal use, not Developer ID notarized, so each Mac may require
right-click Open once and must grant Accessibility permission to Bryan Tools for
automatic paste.

## Test

This local Command Line Tools install does not provide `XCTest` or Swift
`Testing`, so Bryan Tools includes a framework-free self-test runner:

```sh
Scripts/test.sh
```

## Update an existing install

```sh
Scripts/update.sh
```

The update script refuses to run with local checkout changes, pulls with
`--ff-only`, runs self-tests, quits any running Bryan Tools instance, installs a
release build, and relaunches the app. Set `LAUNCH_APP=0` to skip the relaunch.

## Data

Clipboard History stores data locally in Application Support:

```text
~/Library/Application Support/Bryan Tools/Clipboard History/
```

On first launch, Bryan Tools copies existing ClipMan data from
`~/Library/Application Support/ClipMan/` into the new Clipboard History
location. The old ClipMan data is left in place as a rollback backup.

The SQLite database remains `ClipMan.sqlite` for compatibility with the copied
ClipMan data, and raw pasteboard payloads live under `Blobs/`.
