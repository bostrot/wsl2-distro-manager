# Phase 05: Implement the WSL Feature Gaps

This phase turns the Phase 04 audit into shipped functionality. Small gaps get patched into the existing editors; larger missing surfaces get **implemented**, not logged. Work the ordered implementation list in `doc/audit/wsl-docs/index.md` from the top, and treat that list — not this document — as the authoritative scope, since it is based on what was actually measured against the cloned docs.

Every setting added must be gated on the minimum WSL version recorded in the audit, must tell the user when `wsl --shutdown` is required to take effect, and must have real translations in all nine locales. Reuse the existing patterns: `settingSwitch` / `settingText` in `lib/dialogs/settings_dialog.dart` for `wsl.conf`, and the `_settings` controller map plus its toggle/combo/size/file-picker renderers in `lib/screens/settings_screen.dart` for `.wslconfig`. Do not invent a second settings mechanism.

## Tasks

- [x] Implement every **S**-sized `.wslconfig` finding in `lib/screens/settings_screen.dart`:
  - Add each missing key with the correct widget type (toggle for booleans, combo box with the documented enum values, size field with postfix, file picker for paths)
  - Correct any key whose widget type or default the audit marked wrong
  - Update tooltips whose text the audit marked outdated, using current documentation wording
  - Make sure the clear/reset path (`_settings` clearing and the known-keys list around line 299) includes every new key so stale values cannot survive

  **Done 2026-08-28.** Closes ordered-list items **P05-01, P05-09, P05-10, P05-11, P05-12**.

  - **No key was missing.** [[wslconfig-keys]] measured 27 / 27 keys already rendered, so the
    first bullet had nothing to add; the work was widget types, dependencies and text. The two
    unscheduled keys (`systemDistro`, `kernelDebugPort`) stay out — they are Intune-only and
    carry no reference-table row.
  - **P05-01** — new `lib/components/wsl_size.dart`: `parseWslSize` / `parseWslCount` /
    `wslSliderFits` / `formatWslSize`. `_numericSetting` (`settings_screen.dart:1394`) checks
    `wslSliderFits` *before* constructing the `Slider`, so `memory=8589934592`,
    `memory=6144MB` and `processors=64` no longer trip `fluent_ui`'s range assert. Anything the
    slider cannot place renders as a text box carrying `settingoutofrange-text` /
    `settinginvalidsize-text` and is saved byte-for-byte as written — no clamped lie, no snap
    to `1GB`. `SettingsType.number` was split out of `size` so a count key is never read as
    bytes. 17 unit tests in `test/wsl_size_test.dart`.
  - **P05-09** — `SettingsType.enumeration` + `_enumerationBox` (`:1345`): `networkingMode`
    (`none | nat | bridged | mirrored | virtioproxy`, `bridged` labelled with
    `deprecatedvalue-text`) and `autoMemoryReclaim` (`disabled | gradual | dropCache`). A value
    already in the file that is not one of the options is kept as an extra item rather than
    dropped, so opening the screen never rewrites a hand-set value and never trips `ComboBox`'s
    own value-must-be-an-item assert.
  - **P05-10** — all five documented dependencies honoured via the new `enabled` /
    `disabledReason` parameters, disabled with a stated reason rather than hidden:
    `dnsTunneling → {bestEffortDnsParsing, dnsTunnelingIpAddress}`,
    `autoProxy → initialAutoProxyTimeout`,
    `networkingMode=mirrored → {ignoredPorts, hostAddressLoopback}`,
    `networkingMode=nat → dnsProxy`, and `localhostForwarding` greyed with
    `ignoredinmirrored-text` under `mirrored`. `_configBool` reads an *absent* boolean as its
    documented default, so an untouched `dnsTunneling` does not grey out the keys it gates.
  - **P05-11** — `swap` on a size slider (0 … 2× host RAM, `0` disables), `defaultVhdSize` as a
    validated size box, `vmIdleTimeout` and `initialAutoProxyTimeout` as numeric boxes with
    `milliseconds-text` in the label and their documented defaults as placeholders,
    `maxCrashDumpCount` numeric with placeholder `10`, and file pickers on `kernel` and
    `swapFile` through the extracted `_filePickerSuffix` (which `kernelModules` now shares).
  - **P05-12** — 26 tooltips rewritten and `unusedmemoryinfo-text` deleted, **in all nine
    locales** with real translations (`Working/wslconfig-tooltip-i18n.json`, applied by
    `Working/update_i18n_keys.dart`). Restores every "Only applicable when…" clause and every
    documented default, restores `safeMode`'s Win 11 / WSL 0.66.2+ floor and "logical" to
    `processors`, deletes `guiApplications`' invented Windows 11 restriction (V-3), and fixes
    "Only available ,for Windows 11", "Build 19041 and ,later" and "take affect".
    `globalconfigurationinfo-text` now states the restart as unconditional, per [[runtime]]
    R-11. Three new keys — `settingoutofrange-text`, `settinginvalidsize-text`,
    `settinginvalidnumber-text` — added to all nine locales and pinned in `test/locales_test.dart`.
  - **Clear/reset path:** no new key means the `experimentalKeys` list (`:303`) needed no
    change; re-checked that all seven `[experimental]` keys are in it, so none of them is
    re-emitted into `[wsl2]`. The *section-blind writer itself* is P05-02, not this item.
  - **Deliberately not done here.** **P05-04** (tri-state booleans) is excluded on the audit's
    own instruction — it hard-depends on P05-02, because the app still has no way to *remove*
    a key from `.wslconfig`, so "unset" has nowhere to be written. The tooltips now state each
    documented default as the interim mitigation. **P05-07** (Restart-WSL-on-Save prompt) is a
    separate ordered-list item; only its two English defects, which P05-12 owns, were fixed.
    `kernel` / `swapFile` pickers still write single-backslash paths — the escaping is
    P05-02's (CC-10), and the pickers are no worse than typing the path by hand.
  - **Verification:** `flutter test` 410 passing (was 393), `flutter analyze` clean of new
    issues, `dart run scripts/check_translations.dart` exit 0. The running-app pass over the
    written `%USERPROFILE%\.wslconfig` and the screenshots are the last task in this document.

- [x] Implement every **S**-sized `wsl.conf` finding in `lib/dialogs/settings_dialog.dart`:
  - Add the missing sections and keys (`[network]` hostname/generateHosts/generateResolvConf, `[interop]` enabled/appendWindowsPath, `[user]` default, `[boot]` command, and anything else the audit lists)
  - Extend the "clear known wsl.conf settings" list (around line 400) with every new `section-key` pair so switching distros cannot leak values between them
  - Verify round-tripping through `getWslConf`/`setWslConf` in `lib/api/wsl.dart` for each new key, including values containing spaces and `=`

  **Done 2026-08-28.** Closes ordered-list items **P05-03, P05-04** (`wsl.conf` half),
  **P05-05, P05-06, P05-13, P05-14**.

  - **Four of the five listed keys were already there.** [[wslconf-keys]] measured 11 / 15,
    and `[network]` hostname/generateHosts/generateResolvConf, `[interop]`
    enabled/appendWindowsPath and `[boot]` command were all among the eleven. The real gaps
    were `[user] default`, `[boot] protectBinfmt`, `[gpu] enabled` and
    `[time] useWindowsTimezone` — all four now render, so all fifteen documented keys are
    editable.
  - **P05-03 came first, and it is why this item is one commit.** The third bullet asks for
    a round trip through the writer, and the writer could not do one: `settings.bash`
    templated `PARENT`/`KEY`/`VALUE` into a `sed` and an `echo -e "…"` that ran as root.
    New `lib/api/wsl_conf.dart` — `WslConfFile.parse` / `get` / `set` / `remove` /
    `serialize` — is a section-aware, comment-preserving, case-insensitive model;
    `WSLApi.readWSLConf` / `writeWSLConf` / `updateWSLConf` (`wsl.dart:1806`) read the file,
    mutate the model and write the whole thing back **base64-encoded**, so no value is ever
    interpreted by a shell. That closes CC-1, CC-2, CC-7 and V-7 as one fix.
    `assets/scripts/settings.bash` and its `pubspec.yaml` asset entry are deleted.
    `setSetting` now returns the *real* status: a read-only `/etc/wsl.conf` reports failure
    through the new `wslconfwritefailed-text` instead of returning `true` under
    `showOutput: false`.
  - **A missing distro is not an empty file.** `readWSLConf` returns null when wsl.exe
    itself fails, so a distro that will not start is never overwritten with just the key the
    user toggled; a file that merely does not exist parses as empty and is created.
  - **Encoding fix found by running it.** `wsl.exe` answers on stderr in **UTF-16** — this
    machine emits [[runtime]] R-1's "Geschachtelte Virtualisierung wird … nicht
    unterstützt" on every `--exec` — and a strict `utf8` decoder throws `FormatException`
    on that rather than returning it. Both new calls read raw bytes and decode through the
    existing `utf8Convert`. Captured in `Working/phase-05-task02-runtime-probe.txt`.
  - **P05-04 (`wsl.conf` half)** — `WslConfSetting.defaultOn` carries the documented
    default, so the six documented-`true` toggles render **on** when the key is absent
    instead of off (CC-3), each unset key says `settingunset-text`, and an undo button
    physically **removes** the line so WSL's own default applies again. `[boot] systemd`
    deliberately carries no default — it is whatever the distro image ships. The
    `.wslconfig` half stays blocked on P05-02, as the audit instructs.
  - **P05-05** — `[user] default` is a real editor now, placed directly under the **Start
    user** box with `wsldefaultuser-text` / `defaultuserinfo-text`, and Start user gained
    `startuserinfo-text` saying it only applies to terminals this app launches
    ([[coverage-sweep]] S-1). Preferring `--manage --set-default-user` needs P05-08's
    version gate, so this writes the key — the documented mechanism, and the only one that
    works for an imported distro.
  - **P05-06** — text keys commit on a 700 ms debounce and on blur/submit instead of once
    per character (CC-5); an emptied box removes the key rather than pinning an empty value.
    The editor states the restart rule (`wslconfrestart-text`) and carries a **Terminate
    distro** button — per-distro, not a global shutdown, per [[runtime]] R-12.
  - **P05-13** — every key has a localised label and description from the nine-locale set
    committed in `65d5ec5`; nothing is derived from a Dart identifier any more.
    `automountoptionsinfo-text` names all seven tokens and states the `metadata`
    precondition. Two further keys — `startuserinfo-text`, `wslconfwritefailed-text` — were
    added to all nine locales with real translations
    (`Working/wslconf-dialog-i18n.json`, applied by `Working/update_i18n_keys.dart`) and
    pinned in `test/locales_test.dart`.
  - **Clear/reset path:** the hardcoded twelve-key list is gone; `loadDistroSettings` now
    derives it from `wslConfSettings`, so a key that is rendered cannot be forgotten there.
    A widget test asserts every rendered key is cleared before the file is read.
  - **Verification:** `flutter test` 480 passing (was 410) — 40 in the new
    `test/wsl_conf_test.dart`, 15 in the new `test/settings_dialog_test.dart`, 10 in
    `test/wsl_test.dart`, 5 in `test/locales_test.dart`. `flutter analyze` reports 0 errors
    and 105 issues, down from 109. `dart run scripts/check_translations.dart` exit 0.
    `flutter test integration_test/` is `+17 -4`, byte-identical to the pre-existing
    `Working/phase-02-task05-integration.txt` — the same four files fail to attach a debug
    connection in this headless session. The writer was also exercised against a real
    **WSL 2.6.3** distro on a scratch path (`Working/probe_wslconf.dart`): slashes, `"`,
    backticks, `$(…)` and single quotes all round-trip byte-identically, a missing file
    reads as empty with exit 0, a read-only target exits 1, and an unreachable distro exits
    non-zero.
  - **Deliberately not done here.** The `[automount] options` per-token editor is an **M**
    the audit explicitly deferred (*Not scheduled*: "no reported demand") — P05-13 supplies
    the description, which is what the #224-class confusion needs.

- [x] Implement the **M**-sized surfaces from the audit list, most impactful first. Typical candidates, to be confirmed against `doc/audit/wsl-docs/features.md`:
  - Networking mode surface: `networkingMode` mirrored plus its dependants (`firewall`, `dnsTunneling`, `autoProxy`, `hostAddressLoopback`), grouped so mutually exclusive options cannot be set together
  - Disk surface: `sparseVhd` global plus per-distro `wsl --manage <distro> --set-sparse`, wired next to the existing compact/VHD actions
  - Any documented `wsl.exe` flag the app should be using instead of a hand-rolled equivalent (e.g. `--manage --move`, `--import --vhd`, `--export --vhd`)

  **Done 2026-08-28.** Closes ordered-list items **P05-02, P05-08, P05-15, P05-16, P05-23** —
  every remaining **M** in the list — plus the `.wslconfig` half of **P05-04**, which P05-02
  unblocked.

  - **The ordered list, not the bullets above, set the scope.** Of the three bullets, the
    networking-mode surface was already shipped by P05-09/P05-10 in this document's first
    task, and `--import --vhd` is already what `copyVhd` uses. `--export --format` and
    `--import-in-place` are **S** items (P05-17, P05-18) scheduled below the M block, so
    they stay for a later pass; `--export --vhd` is marked **n/a** by [[cli-flags]] — the
    shipping binary offers only `--format`. What was left in the M column was P05-02, P05-08,
    P05-15, P05-16 and P05-23, done in that order.
  - **P05-02 — the `.wslconfig` engine.** New `lib/api/ini_config.dart` holds the model, and
    both config files are now dialects of it: `wsl_conf.dart` shrank to a schema over it
    (its 40 tests pass unchanged) and new `lib/api/wslconfig.dart` is the `.wslconfig` one —
    `#` comments only (R-7), escaped backslashes on the three documented `path` keys
    (CC-10/R-6), the file's own line endings preserved, and the section each documented key
    belongs in. `WSLApi.readConfig`/`setConfig`/`writeConfig` (`wsl.dart:529-635`) are
    replaced by `readWslConfig` / `writeWslConfig` / `updateWslConfig`. `saveSettings` now
    diffs against the values it loaded (`applyWslConfigEdits`) and writes **only what
    changed**, so a hand-edited file survives load → Save byte-identical apart from the
    edited key, and the hardcoded `experimentalKeys` list is gone — the section comes from
    the file first, then the documented table. One key becomes seven fixes: CC-2, CC-3, CC-4,
    CC-5, CC-10, CC-11 and S-3.
  - **P05-04's `.wslconfig` half, now that it can ship.** `_tristateToggle`
    (`settings_screen.dart`) renders an absent boolean as its documented default with an
    "unset" caption and an undo button that **removes** the line. The seven documented-`true`
    keys stop displaying the opposite of the truth (CC-1), and `_configBool` reads its
    fallback from the same `kWslConfigBoolDefaults` table rather than a literal per call site.
  - **P05-08 — the capability service.** New `lib/api/wsl_capabilities.dart`: one
    `wsl --version` + `wsl --status`, cached, exposing `version`, `isStoreWsl`, `atLeast()`
    and `supportsManage`. It parses by **shape, not by the English label**, because the
    output is localised — [[runtime]]'s own machine answers in German. It also carries WSL's
    **stderr** through to the UI, which is the half a version number cannot supply: R-1's
    "nested virtualization is not supported on this computer" and R-4's unknown-key
    diagnostics both arrive with **exit code 0**. The version, the warnings and the update
    buttons render at the top of Global Settings.
  - **P05-15 — `wsl --manage --move`.** `WSLApi.move` now prefers the native verb on
    WSL 2.5+: terminate, one `--manage --move`, update `Path_<distro>`. The export →
    **unregister** → import path stays only as the pre-2.5 fallback. A failed native move is
    **never** retried down the destructive path — turning a recoverable error into an
    unrecoverable one is exactly #280. The Move confirmation now names which of the two is
    about to run (`movenative-text` / `movelegacy-text`), which is what #280 itself asked for.
  - **P05-16 — the disk surface.** New `lib/dialogs/disk_dialog.dart`, on the distro action
    bar next to Compact: allocated (`ext4.vhdx` via `findVhdxPath`, not the stale `Path_`
    pref) against used/free from the documented `wsl --system -d <d> df -k /mnt/wslg/distro`,
    then `--manage --resize` (whole numbers only — `2.5TB` is refused where the reason can be
    shown) and `--manage --set-sparse`, whose description says in so many words that it is
    **not** `[experimental] sparseVhd`. Below WSL 2.5 the controls are disabled with
    `requireswsl-text` rather than failing on wsl.exe's own "Invalid command line option".
    #303's free-space pre-check on Compact already exists (`wsl.dart:1457`) and was left as is.
  - **P05-23 — `wsl --update`**, with `--web-download` for machines where the Store is
    blocked, next to the version display.
  - **Two data-safety holes found while reviewing this change, and closed.** `readWslConfig`
    returns **null** when the file could not be read — an unreachable remote host used to
    read as `''`, so the next Save would have replaced the host's whole `.wslconfig` with the
    one key the user touched. And a native move with an empty target used to canonicalize to
    the process's working directory; it now refuses. Both have tests.
  - **Test isolation the move tests caught.** The first version read
    `WslCapabilityService.instance`, so the **real** `wsl.exe` on the build machine decided
    which branch the tests took. `WSLApi` now resolves its capability service through the
    injected shell, and the app-wide singleton only when there isn't one.
  - **34 new i18n keys with real translations in all nine locales**
    (`Working/phase-05-task03-i18n.json`, applied by `Working/update_i18n_keys.dart`), all
    pinned in `test/locales_test.dart`.
  - **Verification:** `flutter test` **568 passing** (was 480) — 42 in the new
    `test/wslconfig_test.dart`, 17 in `test/wsl_capabilities_test.dart`, 12 in
    `test/disk_dialog_test.dart`, 17 added to `test/wsl_test.dart`.
    `flutter analyze` 105 issues, **0 errors**, byte-identical to the count this document's
    previous task recorded. `dart run scripts/check_translations.dart` exit 0.
    `flutter test integration_test/` is `+17 -4`, the same four debug-connection failures as
    the pre-existing baseline (`Working/phase-05-task03-integration.txt`).
    `git diff --stat` carries **no formatting churn**: `dart format` reflows ~82 unrelated
    lines of `wsl.dart` and ~21 of `list_item.dart`, so each touched file was rebuilt as
    HEAD + this task's hunks only.
  - **Not done here.** The running-app pass and the screenshots are a later task in this
    document, as is updating `doc/audit/wsl-docs/index.md`.

- [x] Implement the **L**-sized surfaces from the audit list. Build each behind the existing screen/route pattern (`lib/nav/router.dart`, `lib/nav/panelist.dart`, `lib/screens/`), following the precedent set by the recently added `create_screen.dart` — a dedicated screen, not a dialog, for anything with long-running progress. Split this task across multiple passes if the audit lists more than one L item, finishing each end to end before starting the next.

  **Done 2026-08-28.** Closes ordered-list item **P05-24**, [[features]] **F-8** — the
  audit's *only* **L**, so this is one pass, end to end. No split was needed.

  - **The shape of the feature, and why it is not tar surgery.** `build-custom-distro.md`
    describes one path — rootfs → gzipped tar → rename to `.wsl` → `wsl --install
    --from-file` — with `/etc/wsl-distribution.conf` inside the archive deciding what
    happens on first launch. The obvious implementation is to export a tar and splice the
    config into it afterwards; it is the wrong trade, because a distro export is routinely
    several gigabytes, appending means either holding it in memory or hand-editing the
    trailing zero blocks, and duplicate-entry precedence on extraction is unspecified for
    WSL's own extractor. So the config is edited **inside the distro**, with the same
    editor pattern as `wsl.conf`, and packaging is then just an export of a distro that
    already contains what it needs. Nothing is injected behind the user's back, the result
    is inspectable with `cat`, and wsl.exe produces the whole archive.
  - **New `lib/api/wsl_distribution_conf.dart`** — the third dialect of
    `ini_config.dart`, after `wsl.conf` (P05-03) and `.wslconfig` (P05-02). Seven
    documented keys across `[oobe]` / `[shortcut]` / `[windowsterminal]`, the two
    documented-`true` boolean defaults, and case-insensitive canonicalisation that
    reconciles the doc's own contradiction: its reference table writes `profileTemplate`
    and its sample file writes `ProfileTemplate`, and a file copied out of either has to
    reach the widget. `documentedSection()` is explicitly **not** usable on this dialect —
    `enabled` belongs to two sections — and every read and write names its section.
  - **`readWSLConf` / `writeWSLConf` generalised** (`wsl.dart:1907`) into
    `readDistroFile` / `writeDistroFile`, so the base64 payload, the
    `2>/dev/null; exit 0` and the UTF-16 stderr decoding are written once rather than
    three times. `writeDistroFile` gained a `mode:` for the `chmod` the docs require —
    `0644` on both config files, `0755` on the OOBE script — and a failed `chmod` is a
    failed write, not a silent one. `readDistroFileList` and `isExecutableInDistro` are
    new: the first is the only probe that builds a script from its arguments and so drops
    anything that is not a plain absolute path; the second runs `test -x` as **argv**,
    because its path comes out of a file the user edits.
  - **`wsl --install --from-file`** (`wsl.dart:2247`) — the documented install path, and
    the half of F-8 the app could not do at all. Unlike `--import` it honours the
    package's `wsl-distribution.conf`, so the result gets its OOBE, its default user, its
    Start-menu shortcut and its Windows Terminal profile — none of which an `--import`ed
    distro has ever had, which is [[wslconf-keys]] CC-6's root cause and #268's. Flags
    read off the shipping binary's own `--help`, not guessed: `--name`, `--location`,
    `--no-launch`. `--no-launch` is the default here because the OOBE script is
    interactive and a GUI has no console to answer it.
  - **`--export --format`** is now a parameter of `WSLApi.export`, defaulting to absent so
    every existing caller keeps writing a plain tar. Packaging passes `tar.gz`, the format
    the docs recommend in so many words. This is the API half of **P05-17** and nothing
    more; wiring it into the template/export UI is still that item.
  - **New `lib/api/distro_package.dart`** — `DistroPackager` (package / install / inspect
    / write the sample OOBE script) plus `packageIssues`, a **pure** function from config
    + probe to a ranked list of problems. Every rule in it is a line of the docs, not a
    preference: a missing `oobe.defaultName` is an error because `:191` states the
    double-click install needs one; a non-executable `oobe.command` is an error because
    "the user won't be able to open a shell"; a command without `defaultUid`, a non-`.ico`
    icon, a missing `/etc/wsl.conf` and a shipped `/etc/resolv.conf` are the four
    "Configuration file recommendations" warnings.
  - **New `lib/screens/package_screen.dart`**, route `/package`, pane item between Add
    instance and Mount. A screen and not a dialog for the reason the task states —
    `wsl --export` over a whole root filesystem runs for minutes — and because the order
    matters: the config has to be right *before* the export freezes it into the package,
    so editor → readiness check → package button sit on one surface in that order. The
    editor holds the parsed file in state rather than mirroring into `SharedPreferences`
    the way the `wsl.conf` dialog does, so there is nothing to keep in step; each write
    re-reads, because a screen showing its own optimistic guess is how a failed write
    reads as a successful one.
  - **Everything is gated on WSL 2.4.4** via new
    `WslCapabilities.supportsWslPackages` — `build-custom-distro.md:16` states the floor
    outright. Below it the screen says so with `requireswsl-text` rather than letting
    `--from-file` come back as wsl.exe's untranslated "Invalid command line option".
  - **`DebouncedTextBox` extracted** to `lib/components/debounced_text_box.dart` and
    `settings_dialog.dart` rewired onto it, rather than writing the 700 ms debounce a
    second time. Its 15 existing widget tests pass unchanged.
  - **Two things the tests found, both fixed.** `installFromFile` did not trim its name,
    so a whitespace-only name became `--name '  '` — which is not "no name", it is wsl.exe
    registering the distro under nothing. And the mock's `cat` branch was per-file, which
    hid that `readDistroFile` had no generic unreachable path; it is now one branch and
    `simulateWslConfUnreachable` covers every in-distro read.
  - **54 new i18n keys with real translations in all nine locales**
    (`Working/phase-05-task04-i18n-*.json`, applied by `Working/update_i18n_keys.dart`),
    all pinned in `test/locales_test.dart`. `selectfile-text` was reused rather than
    adding a second "Browse".
  - **Verification:** `flutter test` **665 passing** (was 568) — 25 in the new
    `test/wsl_distribution_conf_test.dart`, 41 in `test/distro_package_test.dart`, 20 in
    `test/package_screen_test.dart`, 5 added to `test/wsl_test.dart` and 6 to
    `test/locales_test.dart`. `flutter analyze` **0 errors**, 108 issues against a 105
    baseline; the three added are `dangling_library_doc_comments` on the three new test
    files, matching the five test files that already carry it.
    `dart run scripts/check_translations.dart` exit 0.
    `flutter test integration_test/` is `+17 -4`, the same four debug-connection failures
    as the pre-existing baseline (`Working/phase-05-task04-integration.txt`).
    `git diff --stat` carries **no formatting churn**: `dart format` reflows ~160 lines of
    `wsl.dart`, ~120 of `panelist.dart` and ~600 of `wsl_test.dart` that were already
    unformatted at HEAD, so only the hunks this task added were reformatted, by hand.
  - **Not done here.** The running-app pass and the screenshots are a later task in this
    document, as is updating `doc/audit/wsl-docs/index.md`. `wsl --list --online` /
    `DistributionListUrl` manifest publishing is deliberately out: the audit lists
    `--list --online` under *Not scheduled* ("the app ships its own catalogue"), and the
    registry override in `build-custom-distro.md` is an admin test procedure, not a
    settings-screen feature.

- [ ] Wire the new settings into the API layer where they are not just file writes:
  - Extend `lib/api/wsl.dart` for any new `wsl.exe` command, routing it through `ExecutionBroker` with an appropriate timeout — never `Process.run` directly
  - Keep every WSL command string free of double quotes (`runInShell: false` passes `"` through to bash literally)
  - Resolve any disk path through `findVhdxPath()` / `vhdxPathCandidates()`, not the stale `Path_<distro>` preference

- [ ] Write tests for the new surface:
  - Extend `test/wsl_test.dart` for `.wslconfig` and `wsl.conf` read/write round-trips of the new keys, including quoting and unusual values
  - Add tests for any new `wsl.exe` command construction (argument order, flags, timeout)
  - Add tests that version-gated settings are hidden below their minimum WSL version

- [ ] Run `flutter test` and `flutter analyze`, fix all failures, then verify in the running app:
  - Open global settings, set and save each new `.wslconfig` key, and confirm the written `%USERPROFILE%\.wslconfig` matches exactly (read it back with PowerShell)
  - Open per-distro settings on a real distro, set each new `wsl.conf` key, save, and `wsl -d <distro> cat /etc/wsl.conf` to confirm
  - Capture screenshots of every new or changed settings section into `.maestro/screenshots/phase-05/`

- [ ] Update `doc/audit/wsl-docs/index.md` to mark each finding as implemented (with the file and line where it landed) or explicitly deferred with a reason, so the audit stays an accurate map rather than a stale wish list. Format only the touched Dart files, confirm `git diff --stat` shows no unrelated churn, and commit on `beta`.
