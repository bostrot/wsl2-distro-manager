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
| ST-01 | Leaving Settings by any route other than Save silently discards every edit; no unsaved-changes prompt | [[settings-and-tools]] | `settings_screen.dart:88` | blocker | M | `104`/`105`/`107-settings-save-noop.png` |
| ST-02 | Language is the one setting that persists without Save, and needs a restart to show | [[settings-and-tools]] | `settings_screen.dart:607` | major | S | `110-settings-language-de-selected.png` |
| ST-03 | Save navigates away to Home and never confirms that anything was written | [[settings-and-tools]] | `settings_screen.dart:341` | major | S | `100-settings-after-save.png` |
| ST-04 | "Stop WSL" shuts down every distro, sits beside Save, no confirmation, tooltip repeats the label | [[settings-and-tools]] | `settings_screen.dart:208` | major | S | `102b-stopwsl-tooltip-zoom.png` |
| ST-05 | An invalid `.wslconfig` value saves unchallenged; WSL then rejects it on stderr with exit code 0 | [[settings-and-tools]] | `settings_screen.dart:355` | blocker | M | `98`/`100-settings-after-save.png` |
| ST-06 | The invalid-value warning never appears while typing -- only after an unrelated rebuild | [[settings-and-tools]] | `settings_screen.dart:1595` | major | S | `98` vs `99-settings-warning-after-rebuild.png` |
| ST-07 | The "WSL reported:" panel reads the stderr of two commands that never mention `.wslconfig` | [[settings-and-tools]] | `wsl_capabilities.dart:157` | major | M | `101-settings-wslwarnings.png` |
| ST-08 | Memory/Processors/Swap sliders never render: `SysInfo` reports 0 bytes and 1 core (measured) | [[settings-and-tools]] | `settings_screen.dart:1269` | major | S | `91b-memory-processors-zoom.png` |
| ST-09 | Twenty-six settings are labelled with the raw camelCase `.wslconfig` key, untranslated | [[settings-and-tools]] | `settings_screen.dart:1389` | major | M | `93-settings-globalconfig-4.png` |
| ST-10 | The disabled-control explanation renders at 2.51:1 contrast (measured); the line above it is 6.00:1 | [[settings-and-tools]] | `settings_screen.dart:1412` | major | S | `97-settings-localhostforwarding-disabled.png` |
| ST-11 | The disabled reason repeats the description verbatim, 20px below it | [[settings-and-tools]] | `en.json:414` | nit | S | `97-settings-localhostforwarding-disabled.png` |
| ST-12 | The disabled reason names the raw key rather than the label it points at | [[settings-and-tools]] | `settings_screen.dart:1147` | nit | S | `95-settings-mirrored-disables.png` |
| ST-13 | Global-config note tells a GUI user to run `wsl --shutdown`; the button for it is 400px below | [[settings-and-tools]] | `en.json:117` | nit | S | `90-settings-globalconfig-1.png` |
| ST-14 | Every footer button's tooltip is a copy of its own visible label | [[settings-and-tools]] | `settings_screen.dart:192` | nit | S | `102b-stopwsl-tooltip-zoom.png` |
| ST-15 | "true (Default)" and "Not set — using the default" state one fact twice, on one row, x12 | [[settings-and-tools]] | `settings_screen.dart:1491` | nit | S | `93-settings-globalconfig-4.png` |
| ST-16 | An enumeration can never be returned to unset -- no "not set" item and no undo, unlike the booleans | [[settings-and-tools]] | `settings_screen.dart:1527` | major | S | `95-settings-mirrored-disables.png` |
| ST-17 | The enumeration flyout covers its own field and the two settings below, and marks no current value | [[settings-and-tools]] | `settings_screen.dart:1544` | nit | S | `94-settings-networkingmode-open.png` |
| ST-18 | Four unlabelled MCP icon buttons: no tooltip, no `MergeSemantics`, two identical copy glyphs | [[settings-and-tools]] | `settings_screen.dart:809` | major | S | `86-settings-mcp-on.png` |
| ST-19 | One click regenerates the MCP token -- no confirm, no toast, no notice that clients break (measured) | [[settings-and-tools]] | `settings_screen.dart:823` | major | S | `87`/`88-settings-mcp-token-*-crop.png` |
| ST-20 | The public-internet warning shows whenever MCP is on, contradicting the hint two lines above it | [[settings-and-tools]] | `settings_screen.dart:834` | major | S | `86-settings-mcp-on.png` |
| ST-21 | Copy buttons give no feedback at all | [[settings-and-tools]] | `settings_screen.dart:783` | nit | S | `86-settings-mcp-on.png` |
| ST-22 | Tunnel error is a raw `e.toString()` in hardcoded `Colors.red` | [[settings-and-tools]] | `settings_screen.dart:889` | nit | S | _source-derived_ |
| ST-23 | Sync group: no explanation, a plaintext example password in a masked field, and a non-sync setting | [[settings-and-tools]] | `settings_screen.dart:1004` | nit | S | `89-settings-sync.png` |
| ST-24 | "Remote SSH target" stays enabled while the toggle that uses it is off | [[settings-and-tools]] | `settings_screen.dart:556` | nit | S | `82-settings-general.png` |
| ST-25 | Path settings show their effective value as a grey placeholder, so set and unset look identical | [[settings-and-tools]] | `settings_screen.dart:436` | nit | S | `82-settings-general.png` |
| ST-26 | Save materialises a Docker repository default the user never chose | [[settings-and-tools]] | `settings_screen.dart:282` | nit | S | `83-settings-docker.png` |
| ST-27 | Opening the per-distro settings dialog boots the distro (measured: stopped then running) | [[settings-and-tools]] | `settings_dialog.dart:666` | major | S | `113` then `114-distro-settings-loaded.png` |
| ST-28 | Cancel does not cancel: every `wsl.conf` key writes to the distro on change, not on Save | [[settings-and-tools]] | `settings_dialog.dart:69` | major | S | `117-distro-settings-time-expanded.png` |
| ST-29 | Four irreversible actions styled identically to the Expander headers directly above them | [[settings-and-tools]] | `settings_dialog.dart:466` | major | S | `116-distro-settings-bottom.png` |
| ST-30 | The sync buttons' tooltips ("Upload"/"Download") do not match their labels | [[settings-and-tools]] | `settings_dialog.dart:175` | nit | S | `116-distro-settings-bottom.png` |
| ST-31 | "Start/Stop serving on network" never shows which state it is in; `isSyncing` is never persisted | [[settings-and-tools]] | `settings_dialog.dart:108` | nit | S | `116-distro-settings-bottom.png` |
| ST-32 | A twenty-control form capped at 500x500, three fields visible at a time | [[settings-and-tools]] | `settings_dialog.dart:60` | nit | S | `114-distro-settings-loaded.png` |
| ST-33 | The dialog is titled "Settings" with no distro name -- same word as the app-wide screen | [[settings-and-tools]] | `settings_dialog.dart:48` | nit | S | `114-distro-settings-loaded.png` |
| ST-34 | The same "unset" concept has two visual languages; the dialog's looks like a hyperlink | [[settings-and-tools]] | `settings_dialog.dart:528` | nit | S | `117-distro-settings-time-expanded.png` |
| ST-35 | The user section labels itself twice and hosts an orphaned parenthetical between two groups | [[settings-and-tools]] | `settings_dialog.dart:157` | nit | S | `118-distro-settings-userfield.png` |
| ST-36 | Loading is an unlabelled spinner for 4s+ with Cancel and Save both enabled | [[settings-and-tools]] | `settings_dialog.dart:722` | nit | S | `113-distro-settings-dialog.png` |
| ST-37 | A template under ~5MB formats to "0 GB" and is silently removed from the list | [[settings-and-tools]] | `template_screen.dart:126` | major | S | _source-derived_ |
| ST-38 | Deleting a template asks "Delete instance ... permanently? / If you delete this Distro..." | [[settings-and-tools]] | `template_screen.dart:185` | major | S | `121-templates-delete-confirm.png` |
| ST-39 | "Create a new instance" opens a dialog titled "Copy", about "the WSL instance" | [[settings-and-tools]] | `template_screen.dart:158` | major | S | `122-templates-create-dialog.png` |
| ST-40 | Template delete is a bare icon 900px from the labelled buttons, no tooltip, no destructive styling | [[settings-and-tools]] | `template_screen.dart:182` | nit | S | `120-templates-expanded.png` |
| ST-41 | No title, no explanation of what a template is, and no way to create one from this screen | [[settings-and-tools]] | `template_screen.dart:86` | nit | S | `119-templates-empty.png` |
| ST-42 | Template sizes render as "0.01 GB" | [[settings-and-tools]] | `templates.dart` | nit | S | `119-templates-empty.png` |
| ST-43 | The new-instance name box looks pre-filled -- the placeholder is the template's own name | [[settings-and-tools]] | `base_dialog.dart:64` | nit | S | `122-templates-create-dialog.png` |
| ST-44 | The disk about to be mounted is identified by a truncated, tooltip-less string | [[settings-and-tools]] | `mount_dialog.dart:334` | major | S | `123-mount-dialog-physical.png` |
| ST-45 | The primary button silently no-ops on an empty required field (measured on Unmount) | [[settings-and-tools]] | `mount_dialog.dart:82` | major | S | `125-mount-unmount-empty-noop.png` |
| ST-46 | Nothing says a physical mount needs elevation and detaches the disk from Windows until it fails | [[settings-and-tools]] | `mount_dialog.dart:232` | major | S | `123-mount-dialog-physical.png` |
| ST-47 | Three radio buttons used as a tab strip; the title stays "Mount Disk" in unmount mode | [[settings-and-tools]] | `mount_dialog.dart:266` | nit | S | `124-mount-dialog-unmount.png` |
| ST-48 | With nothing mounted the picker vanishes instead of saying the list is empty | [[settings-and-tools]] | `mount_dialog.dart:512` | nit | S | `124-mount-dialog-unmount.png` |
| ST-49 | The mount-options placeholder is cut off mid-clause with no tooltip | [[settings-and-tools]] | `en.json` | nit | S | `123-mount-dialog-physical.png` |
| ST-50 | Partition / Filesystem Type labels sit 18px apart vertically | [[settings-and-tools]] | `mount_dialog.dart:374` | nit | S | `126-mount-dialog-vhd.png` |
| ST-51 | The VHD browse button uses a different folder glyph from every other picker, and no tooltip | [[settings-and-tools]] | `mount_dialog.dart:428` | nit | S | `126-mount-dialog-vhd.png` |
| ST-52 | The dialog never says which distro the disk lands in or where it appears | [[settings-and-tools]] | `mount_dialog.dart:315` | nit | S | `123-mount-dialog-physical.png` |
| ST-53 | Snippet Save with an empty name silently does nothing -- the error branch is `// Error` | [[settings-and-tools]] | `actions_screen.dart:234` | major | S | `129-actions-save-empty-noop.png` |
| ST-54 | Deleting a snippet asks "Delete instance ... permanently? / If you delete this Distro..." | [[settings-and-tools]] | `actions_screen.dart:330` | major | S | `133b-actions-delete-confirm-zoom.png` |
| ST-55 | Expanding a one-line snippet opens a 430px panel that is 97% empty | [[settings-and-tools]] | `actions_screen.dart:354` | major | S | `132-actions-expanded.png` |
| ST-56 | One object, four names: Snippets / snippet / "Name of setting" / quick action | [[settings-and-tools]] | `actions_screen.dart:76` | nit | S | `128-actions-editor.png` |
| ST-57 | "(by you)" is hardcoded English and "[v0.0.0]" invented; measured 4.41:1 and 3.96:1, both sub-AA | [[settings-and-tools]] | `actions_screen.dart:270` | nit | S | `132-actions-expanded.png` |
| ST-58 | The code editor has no frame, background or label -- 580px of invisible click target | [[settings-and-tools]] | `actions_screen.dart:415` | nit | S | `128-actions-editor.png` |
| ST-59 | The editor hardcodes `atomOneLightTheme`, so syntax colours ignore the app theme | [[settings-and-tools]] | `actions_screen.dart:451` | nit | S | _source-derived_ |
| ST-60 | Nothing says a snippet is a root bash script in a distro, and it cannot be run from this screen | [[settings-and-tools]] | `actions_screen.dart:373` | nit | S | `127-actions-empty.png` |
| ST-61 | Two "add" affordances in opposite corners; "Add Community snippets" capitalises its middle word | [[settings-and-tools]] | `actions_screen.dart:109` | nit | S | `127-actions-empty.png` |
| ST-62 | "Cancel" is the left button in three dialogs and the right button in the one that deletes things | [[settings-and-tools]] | `base_dialog.dart` | major | S | `121` vs `113`/`123`/`135` |

## Per-area files

| File | Covers | Status |
|:---|:---|:---|
| [[list-and-navigation]] | distro list, list rows, nav pane, title bar, narrow width | **done** -- 26 findings (LN-01..LN-26) |
| [[create-and-install]] | create screen, install/copy/QA dialogs | **done** -- 40 findings (CI-01..CI-40) |
| [[settings-and-tools]] | app settings, per-distro settings, templates, mount, actions | **done** -- 62 findings (ST-01..ST-62) |
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
- **The Cloudflare tunnel path in MCP settings** -- enabling it downloads `cloudflared`
  and publishes this machine's MCP server, which can run arbitrary commands in every
  distro, to a public URL. Deliberately not triggered; ST-22 is read from source and
  labelled as such in [[settings-and-tools]].
- **A real disk mount** -- no spare physical disk or `.vhdx`, and `wsl --mount` of a disk
  Windows is using is not something to try on the audit machine. The mount forms, the
  empty-unmount state and the empty-field guard were exercised (ST-44..ST-52); no disk was
  attached, and the four mount/unmount error-recovery dialogs
  (`mount_dialog.dart:110-251`) were never reached.
- **Sync over the network** (`Sync().startServer()`, `download()`) -- needs a second
  machine. ST-23, ST-30 and ST-31 are about the controls, not the transport.
- **`Move`, and `Templates().useTemplate()`** -- the confirmations were opened and
  cancelled (ST-29, ST-39, `122`); neither operation was run, so no distro was
  export/unregister/imported and no instance was created from a template.
- **The zero-template state and the sub-5MB template disappearance** -- one real template
  (`test-4`) exists here; ST-37 is read from source and `notemplates-text` was not reached.
