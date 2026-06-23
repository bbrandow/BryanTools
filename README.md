# Bryan Tools

Bryan Tools is a personal macOS productivity superapp. It runs as a single menu
bar application and hosts a set of independent tools behind one installed app,
shared menu bar controls, and one set of macOS permissions.

The app is intentionally local-first and personal-use focused. It is not built
for public distribution, but the codebase keeps the tools modular so new
utilities can be added without coupling their interfaces together.

## Tools

| Tool | Default shortcut | Purpose |
| --- | --- | --- |
| TrayCal | Menu bar date label | Calendar popover, app settings, and quit control |
| Disk Space Monitor | Menu bar free-space label | Primary-drive free-space sampling and trend chart |
| UTC Hour | Menu bar UTC hour label | UTC-to-Pacific hour lookup table |
| Vehicle Motion Cues | TrayCal footer toggle | One-click on/off control for macOS Vehicle Motion Cues |
| Clipboard History | `Shift-Command-V` | Search, restore, delete, and float clipboard clips |
| Paste Plain Text | `Shift-Option-Command-V` | Paste current clipboard text without formatting |
| Color Picker | `Shift-Command-~` | Pick any screen pixel color as a hex value |
| MacroText | `Shift-Command-/` | Configure global slash-command text replacements |
| QuickTask | `Command-Space`, fallback `Option-Space` | App launcher, calculator, and command runner |
| ShotFloat | `Shift-Command-2` | Capture a screen region into an always-on-top floating image |
| Screen OCR | `Shift-Command-Y` | OCR a selected screen region into the clipboard |
| MouseMacro | Settings UI | Map mouse buttons to keyboard macro sequences |

## Screenshots

The repo does not currently include committed screenshots. Add them under
`Docs/Screenshots/` when useful.

> Screenshot placeholder: `Docs/Screenshots/traycal-popover.png` should show the
> menu bar date label and TrayCal calendar popover with today, payday dots,
> Vehicle Motion Cues, gear, and power controls visible.

> Screenshot placeholder: `Docs/Screenshots/quicktask.png` should show the
> QuickTask command bar with an app match, a calculation result, and command-line
> mode.

> Screenshot placeholder: `Docs/Screenshots/clipboard-history.png` should show
> Clipboard History search results with text, image preview hover, and ShotFloat
> image action.

> Screenshot placeholder: `Docs/Screenshots/settings.png` should show the compact
> settings window with hotkeys, application settings, disk-space settings, and
> MouseMacro mappings.

## Install

Build and install the app bundle:

```sh
Scripts/install-app.sh
```

The installed app is:

```text
/Applications/Bryan Tools.app
```

Bryan Tools is designed to run from this installed location. Auto-start also
targets this path, not a development checkout or `.build` app bundle.

## Run During Development

```sh
Scripts/run-app.sh
```

Build only:

```sh
Scripts/build-app.sh
```

The generated development bundle is written to:

```text
.build/Bryan Tools.app
```

## Update

From an existing checkout:

```sh
Scripts/update.sh
```

The update script refuses to run with local checkout changes, pulls with
`--ff-only`, runs self-tests, quits any running Bryan Tools instance, installs
the app, and relaunches it. Set `LAUNCH_APP=0` to skip relaunch.

The app also exposes an **Update Now** button in Settings. That button resolves
the BryanTools source checkout, validates that it is the expected SwiftPM app,
and runs `Scripts/update.sh`.

## Test

Bryan Tools uses a framework-free self-test runner so it can run with the local
Command Line Tools install:

```sh
Scripts/test.sh
```

## Permissions

macOS permissions are granted to the installed app bundle id:

```text
com.local.BryanTools
```

Expected permissions:

- Accessibility: required for automatic paste, MacroText expansion, global mouse
  macro capture, and synthetic key events.
- Screen Recording: required for Color Picker, ShotFloat, and Screen OCR.
- Input Monitoring may be requested by macOS for low-level input hooks depending
  on system version and security settings.

If permissions behave unexpectedly, confirm they are granted to
`/Applications/Bryan Tools.app`, then quit and relaunch the app.

## Auto Start

Auto-start is enabled by default. On launch, Bryan Tools writes a user
LaunchAgent:

```text
~/Library/LaunchAgents/com.local.BryanTools.autostart.plist
```

The LaunchAgent opens:

```text
/Applications/Bryan Tools.app
```

Disable it from Settings under **Application -> Auto Start**. When disabled, the
LaunchAgent is removed and Bryan Tools will not start automatically after login
or restart.

## Architecture

Bryan Tools has a shared app shell and independent tool modules.

- `BryanToolsApp` owns the macOS lifecycle.
- `BryanToolsEnvironment` wires tools together, starts and stops modules, and
  opens the shared Settings window.
- Each tool implements `ToolModule` and owns its own UI, settings, state, and
  hotkeys.
- Shared services live in `BryanToolsShared` for cross-cutting behavior such as
  hotkeys, app support paths, pasteboard suppression, calendar formatting,
  disk-space storage, OCR text formatting, and updater resolution.
- Clipboard-specific storage, migration, privacy filtering, search, and
  pasteboard archive logic live in `ClipboardHistoryCore`.

Tool UIs should remain independent. If future tools need coordination, they
should communicate through explicit shared services rather than direct
tool-to-tool calls.

## TrayCal

TrayCal is the primary visible menu bar surface. It replaces the old generic app
icon with a date label using this format:

```text
Fri, May 22
```

Clicking the date opens a compact calendar popover.

Features:

- Month grid with Sunday as the first day of the week.
- Today highlight.
- Payday indicators as small green dots. Paydays are every other Friday, anchored
  from May 29, 2026.
- Previous and next month controls.
- Dot button to return to today.
- Clickable month picker.
- Editable year field.
- Gear button to open Bryan Tools Settings.
- Power button to quit Bryan Tools.
- Calendar view resets to today after the popover has been closed for two
  minutes.

> Screenshot placeholder: show TrayCal opened from the menu bar, with the
> current day highlighted and a green payday dot under a Friday.

## Disk Space Monitor

Disk Space Monitor adds a separate menu bar item showing primary-drive free
space, for example:

```text
100GB
```

It samples filesystem metadata only for `/`, avoiding directory scans and
expensive disk traversal.

Features:

- Enabled by default.
- Polls every five minutes while enabled.
- Stores 30 days of samples locally.
- Menu bar tooltip shows the last measurement time.
- Configurable warning threshold in GB.
- Menu bar text turns red below the threshold.
- Popover trend chart with hover details.
- Drag-to-zoom on the chart.
- Reset button after zooming.
- "Now" button to take an immediate measurement.
- Persisted "show last N hours" filter. Blank means full history.

Storage:

```text
~/Library/Application Support/Bryan Tools/Disk Space Monitor/DiskSpace.sqlite
```

> Screenshot placeholder: show the disk-space menu bar label and its popover with
> current free space, last updated time, "Now", "Last hours", and the trend chart.

## UTC Hour

UTC Hour adds a separate menu bar item showing the current UTC hour:

```text
2026-06-16T20
```

It is intended as a quick lookup table for translating UTC hours to Pacific
hours.

Features:

- Enabled by default.
- Menu bar title uses `yyyy-MM-dd'T'HH` in UTC.
- Updates automatically as the current UTC hour changes.
- Popover table compares UTC hour against Pacific hour.
- Pacific rows include date plus 12-hour time, such as `June 17,  1:00am`.
- Pacific midnight rows have a boxed outline to visually break up days.
- Lookup table loads 72 hours before and 72 hours after the current hour.
- Current hour row is highlighted.
- Settings toggle controls whether the menu bar item is shown.

> Screenshot placeholder: show the UTC Hour menu bar label and popover table with
> UTC and Pacific columns and the current hour highlighted.

## Vehicle Motion Cues

Vehicle Motion Cues adds a small car icon to the bottom of the TrayCal popover
for the macOS Accessibility > Motion feature. Clicking the icon toggles the
system Vehicle Motion Cues setting on or off. The icon is filled and accented
while cues are enabled, and outlined/subdued while disabled.

Notes:

- Uses the local macOS Accessibility Motion Cues service; no network calls.
- Does not poll in the background; Bryan Tools manages this from launch and the
  TrayCal footer toggle.
- If the current Mac does not support Vehicle Motion Cues, the icon shows an
  unavailable tooltip.
- Apple limits this feature to supported Mac laptop models.

> Screenshot placeholder: show the Vehicle Motion Cues TrayCal footer icon in
> both on and off states.

## Clipboard History

Clipboard History absorbs the old ClipMan app. It captures clipboard changes,
stores searchable history, and restores selected clips back to the clipboard.

Default shortcut:

```text
Shift-Command-V
```

Features:

- Clipboard capture for text, rich text, files, URLs, images, and mixed
  pasteboard contents.
- Searchable history panel.
- Arrow-key selection.
- Return to copy or paste the selected clip.
- Delete key to delete the selected clip.
- Clear all history.
- Pause capture.
- Retention settings.
- Configurable storage path.
- Hex color clips show a color swatch.
- Image clips show a thumbnail.
- Image hover preview shows a larger image.
- Image clips can be opened in ShotFloat with `Command-Return` or the float
  button.
- Search text auto-clears after the UI has been closed for two minutes.

Storage:

```text
~/Library/Application Support/Bryan Tools/Clipboard History/
```

On first launch, Bryan Tools copies legacy ClipMan data from:

```text
~/Library/Application Support/ClipMan/
```

The old ClipMan data is left in place as a rollback backup.

Security and privacy:

- Stored clipboard metadata, payloads, and thumbnails are encrypted at rest with
  AES-GCM using a Keychain-managed key.
- Private pasteboard markers are skipped.
- 1Password desktop app copies are skipped.
- 1Password browser-extension copies are filtered through browser-source and
  credential-shape detection.
- Browser credential-like strings are skipped where possible, while normal text,
  UUIDs, OTP-shaped values, and color hex codes remain capturable.

Compatibility note: the SQLite file remains named `ClipMan.sqlite` for migrated
data compatibility.

> Screenshot placeholder: show the Clipboard History panel with text results,
> one hex color swatch, one image clip, and the image float button.

## Paste Plain Text

Paste Plain Text rewrites the current clipboard as plain text, posts a paste
command, and then restores the original clipboard when safe.

Default shortcut:

```text
Shift-Option-Command-V
```

Features:

- Converts rich clipboard text to plain text.
- Automatically pastes when Accessibility permission is available.
- Falls back to copying only when automatic paste is not permitted.
- Restores the original clipboard after paste if the clipboard was not changed
  again.

## Color Picker

Color Picker turns the pointer into an eyedropper and copies the selected screen
pixel as a hex color.

Default shortcut:

```text
Shift-Command-~
```

Features:

- Full-screen pixel picking.
- Circular magnifier.
- Hex color output.
- Result is written to the clipboard and appears in Clipboard History.

Requires Screen Recording permission.

> Screenshot placeholder: show the Color Picker magnifier over a colorful UI
> area with the picked hex color visible.

## MacroText

MacroText expands global slash commands into configured replacement text.

Default configuration shortcut:

```text
Shift-Command-/
```

Example:

```text
/name -> Bryan
```

Typing `/name` in another app expands it to `Bryan`.

Features:

- Add, edit, and delete macro replacements.
- Global expansion anywhere macOS allows synthetic input.
- Independent MacroText settings window.
- Dynamic date templates evaluated at expansion time.

Dynamic date examples:

```text
{yyyy-MM-dd'T'hh:-2h}
{yyyy-MM-dd:-1d}
```

If expanded on May 27, 2026 at 3pm, these resolve to:

```text
2026-05-27T13
2026-05-26
```

Supported offsets include hours, days, weeks, months, and years.

Requires Accessibility permission.

> Screenshot placeholder: show the MacroText settings list with commands,
> replacement text, edit controls, and a dynamic date replacement.

## QuickTask

QuickTask is a lightweight command bar for launching apps, calculating values,
and running explicit shell commands.

Default shortcut:

```text
Command-Space
```

If `Command-Space` cannot be registered because Spotlight owns it, QuickTask
falls back to:

```text
Option-Space
```

Features:

- Movable and resizable command bar.
- Typeahead application search.
- Tab and arrow-key selection for app results.
- Return launches the selected app.
- Calculator mode for numeric expressions.
- Parentheses and exponent support.
- Commas while typing and in results.
- Return copies the calculation result to the clipboard.
- Escape closes the bar.
- Reopening after Escape preserves the last entry for two minutes.
- Pressing the hotkey while open hides the bar.

Command-line mode:

- Type `>` as the first character in an empty prompt to enter command mode.
- The `>` becomes the mode icon and is removed from the text input.
- Backspace or Delete on an empty command prompt returns to normal mode.
- Return runs the command with `/bin/zsh -lc` from the home directory.
- Output is displayed in the bar.
- Commands are cancelled when replaced or closed.
- Output is capped and long-running commands time out.

> Screenshot placeholder: show QuickTask in app-search mode, calculator mode,
> and command-line mode with the `>` icon.

## ShotFloat

ShotFloat captures a region of the screen and displays it as a borderless,
always-on-top floating image.

Default shortcut:

```text
Shift-Command-2
```

Features:

- Screenshot-style region reticule.
- No screen dimming overlay.
- Floating image window.
- Drag to move.
- Scroll to zoom in or out, resizing the window with the image.
- Thin top bar with one-click close button.
- Captured image is added to Clipboard History.
- Clipboard History image clips can be opened as ShotFloat images.

Requires Screen Recording permission.

> Screenshot placeholder: show a ShotFloat image floating above another app with
> the close bar visible.

## Screen OCR

Screen OCR captures a screen region, recognizes text locally with Apple Vision,
copies the text to the clipboard, and stores the text in Clipboard History. The
screenshot image is discarded.

Default shortcut:

```text
Shift-Command-Y
```

Features:

- Reuses the same region-selection behavior as ShotFloat.
- Local Apple Vision OCR.
- Accurate recognition level.
- Language correction enabled.
- Recognized lines sorted top-to-bottom, then left-to-right.
- Non-empty OCR text is copied to the clipboard and added once to Clipboard
  History.
- Empty OCR results leave clipboard and history unchanged.
- Escape or right-click cancels without changing clipboard or history.

Requires Screen Recording permission.

> Screenshot placeholder: show the OCR reticule selecting text and the resulting
> recognized text in Clipboard History.

## MouseMacro

MouseMacro maps mouse buttons to keyboard macro sequences.

The first confirmed mapping was the Logitech MX Master 4 haptic button, detected
as Button 6.

Features:

- Capture the next mouse button.
- Add multiple mappings.
- Edit and delete mappings.
- Map a button to a macro string such as:

```text
cmd+shift+ctrl+4
```

Requires Accessibility permission. Depending on macOS settings, Input Monitoring
may also be required for event taps.

> Screenshot placeholder: show MouseMacro settings with Button 6 mapped to
> `cmd+shift+ctrl+4` and another empty mapping row.

## Settings

Settings are opened from the TrayCal gear button. The settings window contains:

- A consolidated hotkey section.
- Clipboard History capture, retention, and storage controls.
- Disk Space Monitor visibility and warning threshold.
- UTC Hour menu bar visibility.
- Application auto-start, updater source, and Update Now controls.
- MouseMacro mapping controls.
- Status messages for tool-specific errors.

## Data Locations

Clipboard History:

```text
~/Library/Application Support/Bryan Tools/Clipboard History/
```

Disk Space Monitor:

```text
~/Library/Application Support/Bryan Tools/Disk Space Monitor/
```

Auto-start LaunchAgent:

```text
~/Library/LaunchAgents/com.local.BryanTools.autostart.plist
```

User preferences:

```text
~/Library/Preferences/com.local.BryanTools.plist
```

## Package a DMG

```sh
Scripts/package-dmg.sh
```

The DMG is written to:

```text
dist/BryanTools-0.1.0.dmg
```

It contains `Bryan Tools.app` and an `/Applications` shortcut. This build is
ad-hoc signed for personal use, not Developer ID notarized, so each Mac may
require right-click Open once and must grant the required macOS permissions to
Bryan Tools.
