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

- [ ] Implement the **M**-sized surfaces from the audit list, most impactful first. Typical candidates, to be confirmed against `doc/audit/wsl-docs/features.md`:
  - Networking mode surface: `networkingMode` mirrored plus its dependants (`firewall`, `dnsTunneling`, `autoProxy`, `hostAddressLoopback`), grouped so mutually exclusive options cannot be set together
  - Disk surface: `sparseVhd` global plus per-distro `wsl --manage <distro> --set-sparse`, wired next to the existing compact/VHD actions
  - Any documented `wsl.exe` flag the app should be using instead of a hand-rolled equivalent (e.g. `--manage --move`, `--import --vhd`, `--export --vhd`)

- [ ] Implement the **L**-sized surfaces from the audit list. Build each behind the existing screen/route pattern (`lib/nav/router.dart`, `lib/nav/panelist.dart`, `lib/screens/`), following the precedent set by the recently added `create_screen.dart` — a dedicated screen, not a dialog, for anything with long-running progress. Split this task across multiple passes if the audit lists more than one L item, finishing each end to end before starting the next.

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
