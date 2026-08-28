# Phase 07: Full Click-Through UI/UX Audit with Screenshots

This phase walks the entire application by clicking through it in a running build, capturing a screenshot of every screen, dialog and meaningful state, and recording UI/UX problems in a structured, navigable audit. Be **nitpicky**: misaligned spacing, inconsistent button order, truncated or overflowing labels, sentence-case versus title-case drift, grey-on-dark text, disabled controls with no explanation, destructive actions without confirmation, spinners with no cancel, empty states with no guidance, and any string that reads like it was written for a developer. Findings are recorded here; Phase 08 fixes them.

Screenshots go to `.maestro/screenshots/phase-07/` (gitignored, never committed). Findings go to `doc/audit/ui-ux/` (committed). Use the `.maestro/tools/` helpers from Phase 01 and remember the two traps: other windows steal focus, and `resize.ps1` must use `MoveWindow` rather than `ShowWindow(SW_RESTORE)`.

## Tasks

- [x] Set up a reproducible audit run:
  - Launch with `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true` so Pro surfaces are reachable
  - Kill the app process before touching `shared_preferences.json` — the app overwrites it on exit, so prefs edits made while it runs are lost
  - Fix the window to a known size via `resize.ps1` (use both a 1400×860 "standard" pass and a deliberately narrow ~900px-wide pass) so screenshots are comparable
  - Create `doc/audit/ui-ux/index.md` with YAML front matter (`type: analysis`, `title: UI/UX Click-Through Audit`, `created: 2026-08-28`, `tags: [ui, ux, audit]`) and a findings table that later files link back to

  **Done 2026-08-28.** Run configuration and how to reproduce it are written up in
  `doc/audit/ui-ux/index.md`; the master findings table and the per-area / fix-list /
  not-examined sections are scaffolded there for the passes below.

  - Added `.maestro/tools/prefs.ps1` (documented in the toolkit README) so the prefs
    baseline is a command rather than a hand edit. It refuses to write while the app is
    running -- the trap this task calls out -- and `-Baseline` pins `language=en`,
    `themeMode=light`, `version`/`LastChangelogVersion` = pubspec version,
    `RatingPromptDone`, today's `LastMotd`, and drops `MoveOp_*`. Read/write goes through
    BOM-less UTF-8 `ReadAllText`/`WriteAllText`: `Get-Content` without `-Encoding UTF8`
    mangles the emoji in `flutter.motd`, and a BOM makes the Dart side fail to parse the
    file, which shows up as "all settings reset".
  - **`WSLM_FORCE_PRO=true` is not a clean baseline on its own.** It returns `true` from
    `_detectStoreInstall()` (`lib/api/license_manager.dart:70`), which sets
    `isStoreLicensed`, and `maybeShowRatingPrompt()` (`lib/dialogs/rating_dialog.dart:20`)
    gates on exactly that -- with `InstancesCreated = 27` here, the very first launch came
    up behind a modal rating dialog. Hence `RatingPromptDone` in the baseline.
  - Pro reachability verified, not assumed: the License screen renders "Pro Plan -- Bought
    once in the Microsoft Store" under the audit build
    (`01-baseline-1400x860-license-pro-check.png`).
  - Both window passes captured and confirmed comparable: `00-baseline-1400x860-home.png`
    (open nav pane, labels visible) and `02-baseline-900x860-home-narrow.png` (compact,
    icon-only -- below fluent_ui's 1008px threshold), plus
    `03-baseline-1400x860-home-restored.png` to show the resize round-trips.
  - No Dart code changed, so no test run: this task added one PowerShell helper and two
    Markdown files. `prefs.ps1` was exercised end to end instead -- throw-while-running,
    `-Backup`, `-Set`, `-Show`, `-Remove`, `-Restore` -- and the prefs file re-verified as
    BOM-less valid JSON with the emoji and the `1183.0` double formatting intact.

- [x] Audit the main list and navigation surface, capturing screenshots of each state:
  - `lib/components/list.dart` / `list_item.dart`: running vs stopped distro rows, the 5-second poll not causing visible flicker, hover and focus states, action button order and iconography, long distro names, a machine with zero distros (empty state)
  - `lib/nav/panelist.dart` sidebar: labels, selected state, `PaneItem.title` must be a real `Text` or the entry has no accessible name
  - Window title bar, theme switch, and the app's behaviour at the narrow width
  - Write findings to `doc/audit/ui-ux/list-and-navigation.md` with front matter, one finding per row: what, where (`file:line`), severity, and the screenshot filename

  **Done 2026-08-28.** 26 findings (LN-01..LN-26) in `doc/audit/ui-ux/list-and-navigation.md`,
  all copied into the master table in `doc/audit/ui-ux/index.md`. 22 screenshots in
  `.maestro/screenshots/phase-07/` (gitignored), including four nearest-neighbour zoom
  crops -- the action-bar and compact-rail defects are not legible at 1:1.

  - **Measured, not eyeballed.** Three findings came out of pixel diffs rather than
    looking: the 5-second poll is *clean* (13 captures 1s apart, 0 changed pixels in the
    list region -- recorded as a verified-pass so the audit doesn't imply a problem);
    six Tab presses on home changed 0 pixels outside the one label that happened to
    update (LN-12), cross-checked against the create screen where the same helper does
    produce a focus ring on Tab 1, so the keystrokes are being delivered; and clicking
    the app-bar back arrow on `/templates` changed 0 pixels (LN-13).
  - **Two findings were reproduced by driving state through `prefs.ps1`** rather than
    waiting for them: a 97-char `DistroName_Ubuntu` for the long-name pass (LN-01,
    LN-23), and `UseRemoteWSL` + an unreachable `RemoteWSLTarget` to force the list's
    error and loading branches (LN-17, LN-18, LN-20), which are otherwise unreachable on
    a healthy host. Baseline restored afterwards; original prefs backed up to
    `%TEMP%\wslm-prefs-p07-list.json`.
  - **LN-03 is the one to fix first.** `home_screen.dart:109` builds a new `GlobalKey`
    on every build, so toggling the AI panel tears down the whole list subtree --
    verified by expanding a row, clicking the toggle, and watching it collapse. Same
    root cause leaks `reloadEvery5Seconds()`'s never-terminating `for(;;)` loop once per
    teardown (stated from source; the `wsl.exe` process-count measurement was too noisy
    to support a claim, so it is not presented as one).
  - **LN-21/LN-22 are labelled source-derived, not screenshotted.** The zero-distro empty
    state needs the host's real distros deleted, and `HomePage` constructs its own
    `WSLApi()` with no injection seam so it can't be faked in a widget test either. Noted
    in the index's "not examined" section rather than quietly implied to be covered.
  - No Dart code changed -- this task produced two Markdown files and screenshots -- so
    there is nothing new to unit-test. `flutter analyze` was run anyway to confirm the
    tree is unchanged and clean.

- [x] Audit the create and install flows:
  - `lib/screens/create_screen.dart` (the new dedicated screen): field order, validation messages, what happens with an empty name, a duplicate name, a name with spaces or non-ASCII characters, the catalogue dropdown, the custom-rootfs path, install progress, cancel, and the error/retry state
  - `lib/dialogs/install_dialog.dart`, `copy_dialog.dart`, `qa_dialog.dart`: consistency with the screen, button order, destructive-action confirmation
  - Write `doc/audit/ui-ux/create-and-install.md`

  **Done 2026-08-28.** 40 findings (CI-01..CI-40) in `doc/audit/ui-ux/create-and-install.md`,
  all copied into the master table in `doc/audit/ui-ux/index.md`. 45 screenshots in
  `.maestro/screenshots/phase-07/` (gitignored), including four nearest-neighbour zoom
  crops for the toast text and the snippet-selection contrast.

  - **Two real instances were created and destroyed**, so progress/success/error are
    captured from actual runs, not reasoned about. `AuditTest` installed Ubuntu 24.04 end
    to end (CI-16: the toast stalls at "Downloading 100%" for the whole `wsl --import`
    phase); `AuditFail` was pointed at `C:\nope\missing-rootfs.tar.gz` to reach the error
    branch. `AuditTest` was `wsl --unregister`ed and prefs restored from
    `%TEMP%\wslm-prefs-p07-create.json` afterwards -- `wsl --list` and a prefs `-Show`
    both re-verified.
  - **CI-17 is the one to fix first.** `Notify.message('creatinginstance-text',
    loading: true)` is never cleared on any of `createInstance`'s seven `return false`
    paths, so 30+ seconds after the red failure banner appeared the status bar still read
    "Creating instance. This might take a while..." with a live spinner
    (`57-create-error-stuck-spinner.png`). Measured, not inferred.
  - **CI-34 is the one measured number in this pass.** Selecting a community snippet drops
    its title from `#1A1A1A` on `#FFFFFF` (17.4:1) to `#838689` on `#BBD9F0` (**2.49:1**)
    -- sampled per-pixel out of `66-qa-selected.png`, so selecting an item is what makes
    it unreadable.
  - **CI-08 explains a behaviour the UI actively lies about.** A catalogue pick survives a
    Source Type change, and pressing Create with source "Local RootFS File" and value
    "Ubuntu 24.04" started a *repo download* and succeeded -- the source type visibly
    disagreed with what the app did.
  - **CI-11, CI-13, CI-28, CI-38..CI-40 are labelled source-derived, not screenshotted.**
    No Docker daemon, no spare `.vhdx`, WSL is installed here, and the `passwd` console
    was deliberately not triggered so no passwordless account was left behind. All are
    listed in the index's "not examined" section rather than quietly implied to be covered.
  - No Dart code changed -- `git status` lists only the three Markdown files -- so there is
    nothing new to unit-test. `flutter analyze` was run anyway to confirm nothing regressed:
    182 issues, **0 errors and 2 warnings**, the rest `info` lints, i.e. the tree's
    pre-existing baseline. (Not "clean" -- the earlier phases' notes overstate that.)

- [x] Audit settings, templates, mount and actions:
  - `lib/screens/settings_screen.dart` including everything Phase 05 added: grouping, scroll length, tooltip legibility, which controls need `wsl --shutdown` to take effect and whether the UI says so, save/discard affordances, and whether an invalid value can be saved
  - `lib/dialogs/settings_dialog.dart` per-distro settings; `lib/screens/template_screen.dart`; `lib/dialogs/mount_dialog.dart`; `lib/screens/actions_screen.dart`; `lib/components/qa_list.dart`
  - Write `doc/audit/ui-ux/settings-and-tools.md`

  **Done 2026-08-28.** 62 findings (ST-01..ST-62) in `doc/audit/ui-ux/settings-and-tools.md`,
  all copied into the master table in `doc/audit/ui-ux/index.md`. 43 screenshots in
  `.maestro/screenshots/phase-07/` (gitignored, `80`..`135`), including six
  nearest-neighbour zoom crops -- the MCP token, the Stop WSL tooltip, the memory/processor
  controls and the snippet delete text are not legible at 1:1.

  - **The two blockers are ST-01 and ST-05, and both were driven end to end against the
    files on disk rather than reasoned about.** ST-01: toggling `SafeMode` on and leaving
    Settings via the nav pane left `%USERPROFILE%\.wslconfig` untouched and the toggle unset
    on re-entry; the identical change with **Save** wrote `safeMode = true`. Typing into
    *Default VS Code Command* and leaving the same way lost the value out of
    `shared_preferences.json` too. `dispose()` (`settings_screen.dart:89-98`) calls
    `saveSettings(..., dispose: true)`, so the code intends auto-save and observably does
    not do it -- and there is no Cancel, no dirty marker and no exit prompt either way.
    ST-05: `memory = eight gigabytes` and `processors = 999` saved verbatim, then fed to a
    real distro start, which answered `wsl: Ungültige Speicherzeichenfolge "eight
    gigabytes" für .wslconfig Eintrag "wsl2.memory"` and `wsl2.processors darf die Anzahl
    logischer Prozessoren nicht überschreiten (999 > 10)` **with exit code 0**.
  - **ST-07 came out of that same experiment and is the more interesting half.** The
    "WSL reported:" panel exists precisely to carry those stderr lines to the user, but it
    reads the stderr of `wsl --version` / `wsl --status`, and measured on the broken config
    `wsl --version` exits 0 with *empty* stderr. The panel was blank while WSL was refusing
    three keys. The probe is also cached for the app's lifetime, so even the right command
    would return the pre-edit answer.
  - **ST-08 needed a probe rather than a screenshot.** Memory, Processors and Swap render
    as text boxes where the code declares sliders. A one-off test in this tree printed
    `totalPhysicalMemory=0 cores=1` from `system_info2`, which makes `sizeMax <= sizeMin`
    for all three, so `hasSlider` is false. wsl.exe independently reports 10 logical
    processors on the same machine (from the ST-05 error text), so this is the package
    failing, not an odd host. The probe test was deleted; `git status` lists only the two
    Markdown files.
  - **Three contrast numbers were sampled per pixel, not eyeballed:** the disabled-control
    explanation -- the one sentence saying why a switch will not move -- is **2.51:1**
    (`#9D9D9D` on `#F6F6F6`) against 6.00:1 for the description directly above it (ST-10);
    a snippet's `(by you)` is 4.41:1 and its `[v0.0.0]` 3.96:1, both under AA (ST-57).
  - **ST-06 is a two-screenshot proof.** The invalid-size warning does not appear while
    typing (`98`); toggling an unrelated switch 270px away makes it appear over the
    unchanged input (`99`). The `TextBox` has no `onChanged` and the message is computed in
    `build()`.
  - **The same delete confirmation is reused for three different kinds of object.**
    Deleting a *template* and deleting a *snippet* both ask "Delete instance X
    permanently? / If you delete this Distro you won't be able to recover it"
    (ST-38, ST-54, captured at 2x in `121` and `133b`).
  - **Two dangerous one-click actions with no confirmation:** *Stop WSL*, styled like Save
    and 10px from it, which `wsl --shutdown`s every distro (ST-04); and MCP *regenerate
    token*, measured changing `dWc9-Axyonz9d1ffo4QcEqvTFGM_8Lsn` to
    `1oj80i0T3TVSxvQ0Ek0HGwpdI3sshZQN` in one click with no toast and no notice that
    configured clients break (ST-19).
  - **Nine verified passes are recorded too**, so a later regression is visible: the
    seven-group accordion, the live conditional-dependency graph reading pending edits, the
    documented-default rendering for twelve booleans, a clean 900px narrow pass, the
    `.wslconfig` writer really being a diff, the enumeration preserving unknown values, the
    nine-language list, and `actions_screen`'s correct `MergeSemantics(Tooltip(IconButton))`
    -- which is what makes ST-18 and ST-40 findings rather than a house style.
  - **Host state restored and re-verified:** `.wslconfig` back to 0 bytes from
    `%TEMP%\wslconfig-p07-backup`, prefs restored from
    `%TEMP%\wslm-prefs-p07-settings.json` (`language=en`, `themeMode=light`,
    `quickSettingsTitles` empty, MCP off), and the `audit-demo` snippet deleted through the
    UI. The Cloudflare tunnel and any real disk mount were deliberately not triggered and
    are listed in the index's "not examined" section.
  - No Dart code changed -- this task produced two Markdown files and screenshots -- so
    there is nothing new to unit-test. `flutter analyze` was run anyway: **109 issues, 0
    errors and 2 warnings**, both warnings pre-existing (`wsl.dart:1744`,
    `test/mocks.dart:597`).

- [ ] Audit the Pro surfaces:
  - `lib/screens/ai_workspace_screen.dart`: card layout, the four lifecycle states, error text legibility, progress visibility, dashboard buttons
  - `lib/screens/license_screen.dart`, `lib/components/pro_badge.dart`, `lib/components/beta_badge.dart`: how Pro gating is communicated to a free user — is it clear what they get, without nagging?
  - `lib/components/ai_chat_panel.dart`, `recommendations_panel.dart`, `ai_diagnosis.dart`, and the MCP server surface
  - Write `doc/audit/ui-ux/pro-surfaces.md`

- [ ] Audit theme, locale and text quality — the highest-yield nitpicking:
  - Repeat the main screens in **dark and light** themes and diff the screenshots; flag any hardcoded `Colors.grey`, any low-contrast text, and any icon that disappears against its background
  - Switch through **all nine locales** (de, en, es, hu, ja, pt, tr, zh_CN, zh_TW); capture at least the home, create and settings screens per locale, and flag every truncated label, overflowing button, untranslated English string and machine-translated phrase that reads wrong
  - Verify no locale blanks the app (the `zh_TW`/`zh_HK` class of bug) and that `test/locales_test.dart` still guards the invariant
  - Write `doc/audit/ui-ux/theme-and-locales.md`

- [ ] Audit interaction and accessibility details:
  - Tab order and keyboard reachability on every screen; can a keyboard-only user create, start, stop and delete a distro?
  - Tooltips on icon-only buttons — a fluent_ui `Tooltip` cannot label a `BaseButton` because `IconButton` opens its own semantics container; the fix is `MergeSemantics` around the pair, so flag every icon button lacking it
  - Long-running operations: is there always a spinner, a cancel and an error path? Does anything lock the whole UI unnecessarily?
  - Error text quality: flag every message containing a raw exception, a bare colon, a stack trace or a shell command a user cannot act on
  - Write `doc/audit/ui-ux/interaction-and-a11y.md`

- [ ] Consolidate the findings into `doc/audit/ui-ux/index.md`:
  - One table of every finding, cross-linked with `[[list-and-navigation]]`-style wiki-links to the per-area files
  - Severity (blocker / major / nit) and an effort estimate for each
  - An explicit ordered fix list, most impactful first — this is the input to Phase 08 and must be complete
  - A short "not examined" section for anything skipped (e.g. remote WSL over SSH if no second machine is available), so the audit does not imply coverage it does not have
