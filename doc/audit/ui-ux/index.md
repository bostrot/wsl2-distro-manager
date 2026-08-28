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
| CI-01 | Error banner keeps showing a failure the user already fixed; two contradictory messages at once | [[create-and-install]] | `create_screen.dart:61` | major | S | `33-create-duplicate-name.png` |
| CI-02 | Duplicate name reported twice simultaneously, in two different visual styles | [[create-and-install]] | `create_dialog.dart:501` | major | S | `34-create-duplicate-submit.png` |
| CI-03 | Inline validation message is hardcoded `Colors.red`, bold 12px, unlike every other error | [[create-and-install]] | `create_dialog.dart:507` | nit | S | `33-create-duplicate-name.png` |
| CI-04 | Name silently rewritten (`[^A-Za-z0-9]` -> `_`); an all-non-ASCII name becomes `___` | [[create-and-install]] | `create_dialog.dart:149` | major | S | `36b-create-name-nonascii-zoom.png` |
| CI-05 | Create and Copy sanitise names by different rules; Copy skips the duplicate check | [[create-and-install]] | `copy_dialog.dart:71` | major | M | _source-derived_ |
| CI-06 | Name field has no label -- placeholder only -- while the field below it gets an `InfoLabel` | [[create-and-install]] | `create_dialog.dart:488` | nit | S | `31-create-1400x860-default.png` |
| CI-07 | Name field shows a clear (X) button when the field is empty | [[create-and-install]] | `create_dialog.dart:492` | nit | S | `31-create-1400x860-default.png` |
| CI-08 | Changing Source Type keeps the old value: a catalogue pick sits in "Path to RootFS Archive" | [[create-and-install]] | `create_dialog.dart:425` | major | S | `44-create-source-switch-stale.png` |
| CI-09 | One static tooltip for a field that means six different things; it covers the Source Type box | [[create-and-install]] | `create_dialog.dart:558` | nit | S | `70-create-wrong-tooltip-localdocker.png` |
| CI-10 | "No results" panel repurposed as a fake suggestion row; three hardcoded English strings | [[create-and-install]] | `create_dialog.dart:601` | major | S | `69-create-docker-image.png` |
| CI-11 | `snapshot.hasError` branch is literally empty; no loading state; future refetched per build | [[create-and-install]] | `create_dialog.dart:586` | nit | S | _source-derived_ |
| CI-12 | "Create default user" + empty username silently creates no user and reports success | [[create-and-install]] | `create_dialog.dart:337` | major | S | `41-create-user-toggle.png` |
| CI-13 | Password step opens an external console with no warning and is not awaited | [[create-and-install]] | `wsl.dart:1255` | major | M | _source-derived_ |
| CI-14 | Cancel disabled for the whole install while the nav pane stays live; no way to abort | [[create-and-install]] | `create_screen.dart:127` | major | M | `48-create-progress.png` |
| CI-15 | Create button collapses to a 38px spinner square; the action row jumps sideways | [[create-and-install]] | `create_screen.dart:117` | nit | S | `48-create-progress.png` |
| CI-16 | Progress is a text percentage in a corner toast and stalls at "Downloading 100%" through import | [[create-and-install]] | `create_dialog.dart:119` | major | M | `52-create-after.png` |
| CI-17 | After a failure the "Creating instance..." spinner keeps running indefinitely | [[create-and-install]] | `create_dialog.dart:166` | major | S | `57-create-error-stuck-spinner.png` |
| CI-18 | Status messages never expire and follow the user across screens for minutes | [[create-and-install]] | `root_screen.dart:83` | major | S | `68-qa-download-invisible-selection.png` |
| CI-19 | Every status message renders `InfoBarSeverity.info`; "ERROR:" gets a blue info icon | [[create-and-install]] | `notify.dart:66` | major | S | `63b-copy-empty-name-toast.png` |
| CI-20 | Messages carry severity in shouting capitals ("DONE:", "ERROR:", "WARNING:") | [[create-and-install]] | `en.json:30` | nit | S | `53-create-importing.png` |
| CI-21 | Two near-identical strings for one condition (`entername-text` / `errorentername-text`) | [[create-and-install]] | `en.json:31` | nit | S | _source-derived_ |
| CI-22 | Raw WSL stderr shown verbatim with its error code -- and in the Windows locale, not the app's | [[create-and-install]] | `create_dialog.dart:291` | major | M | `56-create-error-state.png` |
| CI-23 | Only remedy offered is "Diagnose with AI"; with no key it answers with a go-to-Settings toast | [[create-and-install]] | `ai_diagnosis.dart:20` | major | M | `58-create-ai-diagnose.png` |
| CI-24 | On a short window the never-expiring status bar covers the Create/Cancel buttons | [[create-and-install]] | `notify.dart:23` | major | S | `60-create-900x400-short.png` |
| CI-25 | Source-type popup covers the page title, the Name field and the source field | [[create-and-install]] | `create_dialog.dart:518` | nit | S | `71-create-sourcetype-covers-form.png` |
| CI-26 | Six source types are developer jargon, ungrouped, with no description line | [[create-and-install]] | `en.json:307` | nit | M | `42-create-sourcetype-open.png` |
| CI-27 | Turnkey warning is a five-line italic paragraph containing `fake_systemd` and a shell pipeline | [[create-and-install]] | `en.json:48` | major | S | `72-create-turnkey-warning.png` |
| CI-28 | `createDialog()` is dead code and carries the opposite button order to the screen replacing it | [[create-and-install]] | `create_dialog.dart:31` | nit | S | _source-derived_ |
| CI-29 | Copy dialog's primary action is a plain `Button`, equal-width with Cancel -- no visual primary | [[create-and-install]] | `base_dialog.dart:62` | nit | S | `62-copy-dialog.png` |
| CI-30 | Copy dialog looks pre-filled (placeholder = source name) and pops before it validates | [[create-and-install]] | `base_dialog.dart:64` | major | S | `63b-copy-empty-name-toast.png` |
| CI-31 | Nothing warns that a copy duplicates the whole disk and stops the source distro | [[create-and-install]] | `copy_dialog.dart:63` | nit | S | `62-copy-dialog.png` |
| CI-32 | Community dialog's button order is reversed against every other dialog in the app | [[create-and-install]] | `qa_dialog.dart:151` | major | S | `65-qa-community-dialog.png` |
| CI-33 | Community dialog has no title | [[create-and-install]] | `qa_dialog.dart:133` | nit | S | `65-qa-community-dialog.png` |
| CI-34 | Selecting a snippet drops its text contrast from 17.4:1 to 2.49:1 (measured) | [[create-and-install]] | `qa_list.dart:129` | major | S | `66b-qa-selected-zoom.png` |
| CI-35 | Empty search shows a blank 570px panel; selections hidden by the filter are downloaded anyway | [[create-and-install]] | `qa_list.dart:112` | major | S | `67-qa-no-results.png` |
| CI-36 | Snippet download has no progress and no success message; a failure closes as if it worked | [[create-and-install]] | `qa_dialog.dart:158` | major | S | `68-qa-download-invisible-selection.png` |
| CI-37 | Community dialog is full window height, leaving ~300px of dead space around a stray link | [[create-and-install]] | `qa_dialog.dart:135` | nit | S | `65-qa-community-dialog.png` |
| CI-38 | `wsl --install` is a hyperlink that runs an elevated system change, described as text to copy | [[create-and-install]] | `install_dialog.dart:26` | major | S | _source-derived_ |
| CI-39 | "install it with following command" -- missing article, in all nine locales | [[create-and-install]] | `en.json:74` | nit | S | _source-derived_ |
| CI-40 | Hardcoded 20%-black chip invisible in dark theme; `InstallDialog` is an inline panel, not a dialog | [[create-and-install]] | `install_dialog.dart:22` | nit | S | _source-derived_ |

## Per-area files

| File | Covers | Status |
|:---|:---|:---|
| [[list-and-navigation]] | distro list, list rows, nav pane, title bar, narrow width | **done** -- 26 findings (LN-01..LN-26) |
| [[create-and-install]] | create screen, install/copy/QA dialogs | **done** -- 40 findings (CI-01..CI-40) |
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
- **The WSL-not-installed panel** (`install_dialog.dart`) -- WSL is installed on this host,
  so CI-38..CI-40 are read from source and labelled as such in [[create-and-install]].
- **A real Docker Hub pull, a real local `docker save`, and `Import VHDX`** -- no Docker
  daemon and no spare `.vhdx` here. Those three source types were exercised as far as the
  create *form* goes (CI-08, CI-10, CI-26); no image or disk was actually fetched.
- **The `passwd` console window** that the create flow spawns when a default user is given
  (CI-13) -- deliberately not triggered, so the audit does not leave a passwordless
  account on the host.
- **Store-packaged build** -- the audit runs an unpackaged debug build with the Pro gate
  forced. Anything whose appearance depends on real MSIX package identity (the genuine
  free-tier experience, Store purchase flow) is out of scope for the click-through.
