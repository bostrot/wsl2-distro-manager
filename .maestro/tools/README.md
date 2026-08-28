# UI automation toolkit

PowerShell helpers for driving the WSL Manager window from an agent session:
launch it, focus it, click and type into it, and screenshot it.

All coordinates are **window-relative**. `(0,0)` is the top-left of the window's
*visible* frame — the same origin `shot.ps1` captures from — so a coordinate read
off a screenshot in an image viewer lands on the right pixel without arithmetic.

```powershell
$t = ".maestro\tools"
& "$t\launch.ps1" -Mode exe -Width 1280 -Height 800   # start and place the app
& "$t\click.ps1" -X 110 -Y 248                        # nav: "Eine Instanz hinzufügen"
& "$t\type.ps1" -Text "Ubuntu-24.04" -ClearFirst      # fill the name field
& "$t\shot.ps1" -Path ".maestro\screenshots\phase-01\home.png"
```

Every helper resolves the target window the same way and takes the same
overrides: `-Handle <hwnd>`, `-ProcessName`, `-TitleMatch`, and `-Quiet`.
Resolution order is explicit handle → a process named `wsl2distromanager` with a
main window → a visible top-level window whose title contains `WSL Manager`.
Pass `-Handle` when more than one instance is open.

---

## The traps these helpers exist to avoid

These are measured on this machine, not folklore. Each one silently produces a
*plausible but wrong* result, which is why they cost time to rediscover.

### 1. `ShowWindow(SW_RESTORE)` races the app's own geometry restore

The app restores its saved window size from `shared_preferences` shortly after
the window is first shown. A resize issued inside that window appears to work
and then the window snaps back to the saved size a moment later — the resize
looks like it silently did nothing.

`resize.ps1` therefore calls **`MoveWindow` directly and never
`ShowWindow(SW_RESTORE)`**. `launch.ps1` additionally waits `-SettleSeconds`
(default 10) after the window appears before touching its geometry. Pass
`-Restore` to `resize.ps1` only if the window is genuinely minimised.

### 2. Other windows steal the foreground

`SetForegroundWindow` is refused outright unless the calling process already owns
the foreground, and background apps grab it back. `focus.ps1` loops: attach to
the foreground thread's input queue and retry, and if some other window still
holds the foreground, **minimise that window** — until `GetForegroundWindow()`
equals the app handle.

Never minimised: the app itself, the shell/desktop (`Progman`, `WorkerW`,
`Shell_TrayWnd`), and anything matched by `-Protect`. Use `-NoMinimize` to
disable the escalation entirely.

Related: attaching to a thread that is hung or in a modal loop makes
`SetForegroundWindow` block *forever*. `ForceForeground` probes the foreground
window with `SendMessageTimeout(WM_NULL, SMTO_ABORTIFHUNG, 250ms)` and skips the
attach if it does not answer. Without that probe, a stray "Open with" prompt or
a UAC dialog wedges the whole script.

### 3. `GetWindowRect` over-captures by ~8px on every side

Windows 10/11 pad every window with an invisible resize border. `GetWindowRect`
includes it; the frame the user sees does not. Measured on this machine: **7px
left, 7px right, 7px bottom**. That is the source of the old helper's ~8px
desktop bleed on all four sides.

`shot.ps1` uses `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` instead, so
the capture is exact and window content sits flush against the image edges.
Verified: asking `resize.ps1` for 1280x800 produces a 1280x800 PNG, where the
`GetWindowRect` path produces 1294x807 with visible desktop on every edge
(reproduce with `shot.ps1 -Raw`).

`resize.ps1` compensates the same border, so `-Width`/`-Height` are the
**visible** size and round-trip exactly through `shot.ps1`.

### 4. A virtual key with no scan code does nothing in Flutter

Flutter's Windows embedder derives the physical key from the **scan code** in
`lParam`, not from the virtual key code. A `SendInput` with `wScan = 0` is
accepted by Windows and then silently dropped by the framework: `ctrl+a`,
`delete`, `tab` and friends have no effect on a Flutter text field, while typed
characters (a different code path, `WM_CHAR`) work fine — so the failure looks
like "selection shortcuts are broken in this app" rather than a tooling bug.

`_common.ps1` fills `wScan` from `MapVirtualKey(vk, MAPVK_VK_TO_VSC)` on every
key event, exactly as a real keyboard does.

### 5. Keep these scripts pure ASCII

Windows PowerShell 5.1 reads a BOM-less file as ANSI, not UTF-8. A `—` (U+2014)
inside a double-quoted string decodes to `â€"` under CP1252, and that `"`
terminates the string — you get a parse error pointing at a line dozens of lines
away from the real one. Use `--`.

### 6. Do not name a local variable after a `[switch]` parameter

PowerShell variable names are case-insensitive, so `$raw = ...` inside a script
declaring `param([switch]$Raw)` assigns through the parameter's type constraint
and throws `ArgumentTransformationMetadataException` at the *call site*, which
points at the wrong script entirely.

---

## Helpers

### `launch.ps1`

Kills any running instance, starts the app, waits for the window, waits again for
the geometry restore, focuses, optionally resizes, and prints the window handle
on its own line.

| Parameter | Default | Meaning |
|---|---|---|
| `-Mode` | `run` | `run` (`flutter run -d windows`, debug), `profile`, `release`, or `exe` (an already-built binary) |
| `-Width` / `-Height` | unset | Visible size to place the window at; omitted leaves it alone |
| `-SettleSeconds` | `10` | Wait after the window appears, before touching geometry (trap 1) |
| `-BuildTimeoutSeconds` | `600` | How long to wait for a window; a cold `flutter run` build takes minutes |
| `-ForcePro` | off | Adds `--dart-define=WSLM_FORCE_PRO=true` (see below) |
| `-Exe` | auto | Explicit binary for `-Mode exe`; defaults to the Release then Debug build output |
| `-LogPath` | `%TEMP%\maestro-wslm-launch.log` | Where `flutter run` output goes |
| `-KillFlutter` | off | Also kill leftover `dart`/`flutter_tester` processes holding `build\` |
| `-NoFocus` | off | Skip the focus step |

`-Mode exe` is much faster when a build already exists, but gives no hot reload
and cannot carry `--dart-define`.

### `focus.ps1`

Brings the window to the foreground; see trap 2.

| Parameter | Default | Meaning |
|---|---|---|
| `-TimeoutSeconds` | `15` | Throws if the app has not taken the foreground by then |
| `-NoMinimize` | off | Never minimise a stealing window; just keep retrying |
| `-Protect` | empty | Title substrings that must never be minimised |

Returns the window info object (`Handle`, `HandleValue`, `ProcessId`,
`ProcessName`, `Title`).

### `shot.ps1`

Captures the window to a PNG; see trap 3.

| Parameter | Default | Meaning |
|---|---|---|
| `-Path` | `.maestro\screenshots\<timestamp>.png` | Output file; relative paths resolve against the repo root, parent dirs are created |
| `-SettleMs` | `400` | Pause before capturing, so the last interaction has finished rendering |
| `-NoFocus` | off | Do not raise the window first (only safe if nothing overlaps it) |
| `-Raw` | off | Capture the `GetWindowRect` rectangle instead — for demonstrating the bug, not for real screenshots |

Prints the path it wrote. The window is raised first because the capture reads
real screen pixels: anything overlapping is baked into the image.

### `resize.ps1`

Moves and resizes the window; see traps 1 and 3.

| Parameter | Default | Meaning |
|---|---|---|
| `-Width` / `-Height` | `1280` / `800` | **Visible** size; border compensation is applied automatically |
| `-X` / `-Y` | current | Visible top-left position |
| `-Raw` | off | Feed the numbers to `MoveWindow` untouched |
| `-Restore` | off | Opt into `ShowWindow(SW_RESTORE)` when the window really is minimised |

Warns if the window settles more than 2px from the request — usually the
geometry restore still in flight, or a minimum-size constraint.

### `click.ps1`

| Parameter | Default | Meaning |
|---|---|---|
| `-X` / `-Y` | required | Window-relative; **negative counts back from the right/bottom edge** (`-1` is the last pixel) |
| `-Button` | `left` | `left`, `right`, `middle` |
| `-Count` | `1` | `2` gives a double click (gap kept under the 500ms system threshold) |
| `-MoveOnly` | off | Move the cursor without pressing, for hover states |
| `-Screen` | off | Treat `-X`/`-Y` as absolute screen coordinates |
| `-RestoreCursor` | off | Put the cursor back where it was afterwards |
| `-DelayMs` | `90` | Settle time after the click |

Out-of-range points are clamped into the window with a warning.

### `key.ps1`

Named keys and shortcuts; see trap 4. Use `type.ps1` for literal text.

```powershell
& "$t\key.ps1" enter
& "$t\key.ps1" ctrl+a delete
& "$t\key.ps1" tab -Repeat 3
```

Each argument is one chord: `ctrl`/`shift`/`alt` joined with `+`, then one key.
Known keys: `a`–`z`, `0`–`9`, `num0`–`num9`, `f1`–`f24`, `enter`/`return`, `tab`,
`esc`/`escape`, `space`, `backspace`, `delete`/`del`, `insert`/`ins`, `home`,
`end`, `pageup`/`pgup`, `pagedown`/`pgdn`, `up`/`down`/`left`/`right`,
`win`/`lwin`/`rwin`, `apps`/`menu`, `capslock`, `numlock`, `scrolllock`,
`printscreen`, `pause`, `clear`, `add`, `subtract`, `multiply`, `divide`,
`decimal`. Unknown names throw and list the valid set.

`-Repeat N` sends the whole sequence N times. Navigation keys are flagged
`KEYEVENTF_EXTENDEDKEY`.

### `type.ps1`

| Parameter | Default | Meaning |
|---|---|---|
| `-Text` | required | Literal text; newlines are sent as Enter |
| `-ClearFirst` | off | `ctrl+a` then `delete` first, so the field ends up containing exactly `-Text` |
| `-Enter` | off | Press Enter afterwards |
| `-CharDelayMs` | `0` | Per-character pause, for fields with debounced validation or autocomplete that drop burst input |

Text is sent as `KEYEVENTF_UNICODE` scan codes, which bypass the active keyboard
layout. This matters: the layout here is German, so a `VkKeyScan`- or
`SendKeys`-based helper would mangle `y`/`z`, `@`, `/` and the brackets. It also
means **nothing needs escaping** — `+ ^ % ~ ( ) { } [ ]` are typed literally,
unlike with `SendKeys`. Verified by typing `yz@-Test+^%~(1){2}[3]/\` into the
instance-name field and reading all 23 characters back off a screenshot.

### `scroll.ps1`

| Parameter | Default | Meaning |
|---|---|---|
| `-Amount` | `-3` | Wheel notches; **negative scrolls down**, positive up |
| `-X` / `-Y` | window centre | Where to park the cursor first — Windows routes wheel events to the window under the *cursor*, not the focused one |
| `-Horizontal` | off | Send `MOUSEEVENTF_HWHEEL` instead |
| `-Steps` | one per notch | Split the scroll into N events; a single large delta under-scrolls in some scroll views |

### `prefs.ps1`

Reads, patches, backs up and restores `%APPDATA%\com.bostrot\WSL Distro Manager\shared_preferences.json`
**with the app stopped** -- it throws rather than writing while an instance is
alive, because the app rewrites the file on exit and would discard the edit.

| Parameter | Default | Meaning |
|---|---|---|
| `-Baseline` | off | Apply the click-through-audit baseline (see below) |
| `-Set` | none | Hashtable of key/value pairs; the `flutter.` prefix is added for you |
| `-Remove` | none | Keys to delete |
| `-Backup` / `-Restore` | none | Copy the prefs file to / from a path |
| `-Show` | none | Print the given keys (`$null` when absent) instead of the file path |
| `-StopApp` | off | Close a running instance first instead of throwing |

`-Baseline` pins English, the light theme, the pubspec version in both `version`
and `LastChangelogVersion`, `RatingPromptDone`, today's `LastMotd`, and drops
`MoveOp_*` -- i.e. every once-per-start dialog is pre-dismissed, so a screenshot
is never taken through a modal. Window geometry is deliberately left alone:
`resize.ps1` owns it and the app rewrites the saved size on exit anyway.

```powershell
& ".maestro\tools\prefs.ps1" -Baseline -StopApp -Backup "$env:TEMP\wslm-prefs.json"
& ".maestro\tools\prefs.ps1" -Set @{ language = 'ja'; themeMode = 'dark' } -StopApp
& ".maestro\tools\prefs.ps1" -Show language, themeMode
```

Reads and writes go through `[System.IO.File]::ReadAllText/WriteAllText` with an
explicit BOM-less UTF-8 encoding. Both halves matter: `Get-Content` without
`-Encoding UTF8` decodes the file as ANSI and mangles every non-ASCII value in
it, and a BOM written by `Out-File -Encoding utf8` is a parse error on the Dart
side that surfaces as "all settings reset". Windows PowerShell's `ConvertTo-Json`
does preserve the `1183.0` double formatting the Flutter side stores window
geometry in, so a round trip is safe.

### `_common.ps1`

Shared plumbing, dot-sourced by everything else — the P/Invoke surface,
`Get-AppWindow`, `Get-AppBounds`, `ConvertTo-ScreenPoint` and `Confirm-AppFocus`.
**Add new shared behaviour here rather than duplicating it into a helper.**

It also marks the host PowerShell per-monitor DPI aware on load. Without that,
`GetWindowRect`/DWM report physical pixels while `CopyFromScreen` and
`SetCursorPos` are silently rescaled into the DPI-virtualised space, so
screenshots and clicks disagree by the display scale factor on any monitor that
is not at 100%.

---

## Pro features

Licence-gated screens (`Lizenz`, and the Pro paths in AI Workspace) need Pro to
be active. **Never commit an unconditional `return true;` into
`_detectStoreInstall()`** — that ships Pro to every install, and it is what the
`license_manager_test.dart` failures were tracking.

The supported route is a debug-only compile-time flag:

```powershell
flutter run -d windows --dart-define=WSLM_FORCE_PRO=true
# or
& ".maestro\tools\launch.ps1" -ForcePro
```

It is gated behind `kDebugMode`, so a release build ignores it and the flag is
safe to commit.

The gate lives at the top of `_detectStoreInstall()` in
`lib/api/license_manager.dart`, immediately after the `storeInstallCheckOverride`
test seam:

```dart
if (kDebugMode && const bool.fromEnvironment('WSLM_FORCE_PRO')) {
  return true;
}
```

Order matters — the test seam is checked first, so `license_manager_test.dart`
still drives the gate through `storeInstallCheckOverride` regardless of any
dart-define. With no `--dart-define`, `bool.fromEnvironment` is `false` and the
real MSIX package-identity check runs unchanged.

> **Status:** live as of 2026-08-28 (added in
> [[Phase-01-Foundation-Ship-Blockers]]). `-ForcePro` only has an effect on
> `-Mode run` (a debug build); the switch warns when used with a profile or
> release build, where `kDebugMode` is `false` and the flag is compiled out.

**`-ForcePro` also makes the app look Store-*installed*.** The flag returns
`true` from `_detectStoreInstall()`, so `isStoreLicensed` -- not just `isPro` --
is set, and `maybeShowRatingPrompt()` (`lib/dialogs/rating_dialog.dart`) gates on
exactly that. On a machine with `InstancesCreated` past the threshold, a
`-ForcePro` launch therefore opens on a modal rating dialog in the middle of the
window. Run `prefs.ps1 -Baseline` first when the screenshots have to be clean.

## Notes

- The app **overwrites `shared_preferences.json` on exit**. Kill the process
  before editing prefs by hand, or the edit is lost. `launch.ps1` kills any
  running instance first and waits for it to exit for exactly this reason.
  `prefs.ps1` enforces the same rule: it throws rather than writing while an
  instance is alive.
- `.maestro/screenshots/` is gitignored; the helpers in this folder are tracked.
- Written for Windows PowerShell 5.1 (`powershell.exe`), which is what is
  available here. The scripts also run under PowerShell 7.
