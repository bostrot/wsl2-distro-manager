---
type: analysis
title: UI/UX Click-Through Audit
created: 2026-08-28
updated: 2026-08-28
tags:
  - ui
  - ux
  - audit
  - phase-07
related:
  - '[[list-and-navigation]]'
  - '[[create-and-install]]'
  - '[[settings-and-tools]]'
  - '[[pro-surfaces]]'
  - '[[theme-and-locales]]'
  - '[[interaction-and-a11y]]'
---

# UI/UX click-through audit

Every screen, dialog and meaningful state of WSL Distro Manager, walked by hand in a
running build, screenshotted, and picked apart. This file is the index: the run
configuration that makes the walk reproducible, the master findings table, and the
ordered fix list that Phase 08 works from.

Findings live in the per-area files and are copied into the master table here. Each
finding carries a stable ID (`AREA-nn`) so a fix commit can cite it.

## Run configuration

Everything below was captured against this exact setup. Reproduce it before adding a
finding, or a screenshot will not be comparable with the ones already in the audit.

| | |
|:---|:---|
| Build | `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true` (debug) |
| App version | 1.11.0 (`pubspec.yaml`), branch `beta` |
| Standard window | **1400 x 860** visible px -- above fluent_ui's 1008px open/compact nav threshold |
| Narrow window | **900 x 860** visible px -- deliberately below it, so the compact pane is audited too |
| Locale / theme baseline | `en` / light; other locales and dark are a separate pass ([[theme-and-locales]]) |
| Host | Windows 11 Pro 26200, 1 real distro (`Ubuntu`) + `ai-workspace` |
| Screenshots | `.maestro/screenshots/phase-07/` -- **gitignored, never committed** |

### The four commands

```powershell
$t = ".maestro\tools"
& "$t\prefs.ps1"  -Baseline -StopApp -Backup "$env:TEMP\wslm-prefs.json"
& "$t\launch.ps1" -Mode run -ForcePro -Width 1400 -Height 860 -KillFlutter
& "$t\resize.ps1" -Width 900 -Height 860          # narrow pass
& "$t\shot.ps1"   -Path ".maestro\screenshots\phase-07\<area>-<state>.png"
```

`prefs.ps1` (added by this phase) is the piece that makes the run *reproducible* rather
than merely repeatable. It refuses to touch `shared_preferences.json` while the app is
alive -- the app rewrites the file on exit, so an edit made mid-session is silently
discarded -- and `-Baseline` pins the state that otherwise varies run to run:

| Key | Baseline | Why |
|:---|:---|:---|
| `language` | `en` | The dev machine's saved locale is `de`; an audit that starts in German silently mixes the locale pass into every other pass |
| `themeMode` | `light` | Same reason, for [[theme-and-locales]] |
| `version` | pubspec version | Otherwise `initRoot` takes the version-changed branch |
| `LastChangelogVersion` | pubspec version | Suppresses the changelog dialog, which fetches from GitHub and lands on top of the first screenshot |
| `RatingPromptDone` | `true` | See below -- this one bites specifically *because* of `-ForcePro` |
| `LastMotd` | today | Suppresses the once-a-day motd status bar |
| `MoveOp_Distro`, `MoveOp_BackupPath` | removed | Suppresses the "Recovery Detected" dialog left behind by an interrupted move |

**`WSLM_FORCE_PRO=true` also makes the app look Store-installed.** The flag is read in
`LicenseManager._detectStoreInstall()` (`lib/api/license_manager.dart:70`), so it turns
`isStoreLicensed` -- not just `isPro` -- true. `maybeShowRatingPrompt()`
(`lib/dialogs/rating_dialog.dart:20`) gates on exactly that, and this machine has
`InstancesCreated = 27`, well past the threshold of 3. Result: the first launch of the
audit build opened on a modal rating dialog covering the centre of the window
(`00-baseline-1400x860-home.png`, first take). Pre-setting `RatingPromptDone` is what
removes it. Not a product bug -- a real Store user who has created 27 instances is meant
to see that prompt -- but it does mean **an unprepared `-ForcePro` run is not a clean
baseline.**

Pro reachability was verified rather than assumed: the License screen renders
"Pro Plan -- Bought once in the Microsoft Store" under the audit build
(`01-baseline-1400x860-license-pro-check.png`).

### Traps carried over from Phase 01

- `resize.ps1` uses `MoveWindow`, never `ShowWindow(SW_RESTORE)` -- the app restores its
  saved geometry a moment after the window appears and a restore-based resize loses the
  race, silently snapping back.
- `shot.ps1` captures `DWMWA_EXTENDED_FRAME_BOUNDS`, not `GetWindowRect`, so a "1400x860"
  request produces a 1400x860 PNG with no 7px desktop bleed on each edge.
- Other windows steal the foreground; `focus.ps1` escalates to minimising the thief. Do
  not take a screenshot without letting it run first -- the capture reads real screen
  pixels and bakes in anything overlapping.
- The toolkit scripts must stay pure ASCII (Windows PowerShell 5.1 reads a BOM-less file
  as ANSI, and one em dash then breaks a string dozens of lines away).

### Screenshot naming

`<nn>-<area>-<state>[-<theme|locale|width>].png`, e.g.
`02-baseline-900x860-home-narrow.png`. Findings cite the filename, not a path.

## Findings

Populated by the per-area passes below; empty until they run. Severity is
**blocker** (a user cannot complete the task, or the app looks broken) /
**major** (completable but confusing, wrong or ugly enough to notice) /
**nit** (polish). Effort is a rough implementation estimate for Phase 08.

| ID | Finding | Area | Where | Severity | Effort | Screenshot |
|:---|:---|:---|:---|:---|:---|:---|
| LN-01 | Distro name ellipsised at half the row width; ~480px sits empty beside it (`Expanded` + `Flexible` both flex 1 split 50/50) | [[list-and-navigation]] | `list_item.dart:88` | major | S | `18-list-1400x860-long-name.png` |
| LN-02 | Running and stopped rows misalign by ~30px; name jumps sideways when a distro starts/stops | [[list-and-navigation]] | `list_item.dart:70` | major | S | `10-list-1400x860-home.png` |
| LN-03 | Toggling the AI panel collapses every expanded row and restarts the list -- a new `GlobalKey` per build | [[list-and-navigation]] | `home_screen.dart:109` | major | S | `15`/`16-list-expanded-*-aitoggle.png` |
| LN-04 | Nine identical unlabelled icon buttons, Delete between Cleanup and Settings, no destructive styling | [[list-and-navigation]] | `list_item.dart:229` | major | M | `12b-list-actionbar-zoom.png` |
| LN-05 | `visual_studio_for_windows` is a solid glyph among eight outlines | [[list-and-navigation]] | `list_item.dart:281` | nit | S | `12b-list-actionbar-zoom.png` |
| LN-06 | Rename / disk-usage icons unreadable; save-template and copy near-identical | [[list-and-navigation]] | `list_item.dart:238` | nit | S | `12b-list-actionbar-zoom.png` |
| LN-07 | Expanded row ~85% empty with no hint that snippets fill it | [[list-and-navigation]] | `list_item.dart:188` | nit | S | `12-list-1400x860-row-expanded.png` |
| LN-08 | Header icons default size, action-bar icons pinned to 16px, same row | [[list-and-navigation]] | `list_item.dart:62` | nit | S | `12-list-1400x860-row-expanded.png` |
| LN-09 | Hovering a row highlights only the chevron 660px away | [[list-and-navigation]] | `list_item.dart:52` | nit | S | `11-list-1400x860-row-hover.png` |
| LN-10 | BETA badge paints over the AI Workspace icon in compact mode, hiding the only affordance | [[list-and-navigation]] | `panelist.dart:52` | major | S | `13b-list-compact-betabadge-zoom.png` |
| LN-11 | Snippets and Templates icons indistinguishable at 16px | [[list-and-navigation]] | `panelist.dart:26` | nit | S | `13b-list-compact-betabadge-zoom.png` |
| LN-12 | No visible keyboard focus indicator anywhere on home -- six Tabs, zero pixels changed | [[list-and-navigation]] | `root_screen.dart:222` | major | M | `17-list-tab-1..6.png` |
| LN-13 | Back button permanently disabled and inert; renders near-white (enabled-looking) in dark | [[list-and-navigation]] | `root_screen.dart:144` | major | S | `26b-back-dark.png` |
| LN-14 | "Dark Mode" toggle label hardcoded English in all nine locales | [[list-and-navigation]] | `root_screen.dart:212` | major | S | `25-nav-dark-mode.png` |
| LN-15 | Nav labels mix Title Case and sentence case | [[list-and-navigation]] | `en.json` | nit | S | `10-list-1400x860-home.png` |
| LN-16 | Mount Disk / About open modals but look like destinations -- should be `PaneItemAction` | [[list-and-navigation]] | `panelist.dart:82` | nit | S | `23-nav-mountdisk-action.png` |
| LN-17 | List error dumps `Exception: ...` verbatim; three hardcoded English strings | [[list-and-navigation]] | `list.dart:129` | major | S | `21-list-remote-error.png` |
| LN-18 | Error state offers no remedy and no route back to local WSL; Retry repeats the same failure | [[list-and-navigation]] | `list.dart:128` | major | M | `21-list-remote-error.png` |
| LN-19 | "Diagnose with AI" shown to free users, then answers with an upsell toast | [[list-and-navigation]] | `ai_diagnosis.dart:13` | nit | S | `21-list-remote-error.png` |
| LN-20 | Loading top-anchored vs centred results: content jumps 330px; hardcoded string; no cancel | [[list-and-navigation]] | `list.dart:166` | nit | S | `20-list-remote-loading.png` |
| LN-21 | Empty-state CTA and the AI chat button collide in the bottom-right corner | [[list-and-navigation]] | `list.dart:91` | major | S | _source-derived_ |
| LN-22 | Empty-state copy merges two unrelated states and gives no next step | [[list-and-navigation]] | `en.json` | major | S | _source-derived_ |
| LN-23 | Truncated distro names have no tooltip and no way to read them in full | [[list-and-navigation]] | `list_item.dart:92` | nit | S | `19-list-900x860-long-name-narrow.png` |
| LN-24 | AI chat button nearly invisible in both themes; hardcoded `Colors.grey` / `Colors.white` | [[list-and-navigation]] | `home_screen.dart:163` | nit | S | `26-list-1400x860-home-dark.png` |
| LN-25 | Size column unlabelled; silently blanks on failure; never says it is VHDX-on-disk | [[list-and-navigation]] | `list.dart:120` | nit | S | `10-list-1400x860-home.png` |
| LN-26 | Start stays enabled and still says "Start" on a running distro | [[list-and-navigation]] | `list_item.dart:56` | nit | S | `10-list-1400x860-home.png` |

## Per-area files

| File | Covers | Status |
|:---|:---|:---|
| [[list-and-navigation]] | distro list, list rows, nav pane, title bar, narrow width | **done** -- 26 findings (LN-01..LN-26) |
| [[create-and-install]] | create screen, install/copy/QA dialogs | not started |
| [[settings-and-tools]] | app settings, per-distro settings, templates, mount, actions | not started |
| [[pro-surfaces]] | AI Workspace, license, badges, AI chat, recommendations, MCP | not started |
| [[theme-and-locales]] | dark/light diff, all nine locales, text quality | not started |
| [[interaction-and-a11y]] | tab order, tooltips, long operations, error text | not started |

## Ordered fix list

Input to Phase 08. Empty until the passes above produce findings.

## Not examined

Recorded as the audit runs, so it never implies coverage it does not have.

- **Remote WSL over SSH** -- needs a second Windows host; not available here. The *failure*
  path was exercised deliberately by pointing `RemoteWSLTarget` at an unreachable host
  (LN-17, LN-18, LN-20); the happy path was not.
- **The zero-distro home empty state, live** -- reaching it means deleting the host's real
  distros, and `HomePage` constructs its own `WSLApi()` with no injection seam, so it
  cannot be substituted in a widget test either. LN-21 and LN-22 are recorded from source
  and labelled as such.
- **Docker container rows** (`showDocker`) and the `wslNotInstalled` install prompt -- no
  Docker containers on this host, and WSL is installed.
- **The row's quick-actions dropdown with snippets configured** -- none are configured, so
  only the empty branch was seen (LN-07).
- **Store-packaged build** -- the audit runs an unpackaged debug build with the Pro gate
  forced. Anything whose appearance depends on real MSIX package identity (the genuine
  free-tier experience, Store purchase flow) is out of scope for the click-through.
