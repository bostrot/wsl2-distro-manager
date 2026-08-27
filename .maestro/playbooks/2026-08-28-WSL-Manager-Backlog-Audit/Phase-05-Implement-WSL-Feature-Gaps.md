# Phase 05: Implement the WSL Feature Gaps

This phase turns the Phase 04 audit into shipped functionality. Small gaps get patched into the existing editors; larger missing surfaces get **implemented**, not logged. Work the ordered implementation list in `doc/audit/wsl-docs/index.md` from the top, and treat that list — not this document — as the authoritative scope, since it is based on what was actually measured against the cloned docs.

Every setting added must be gated on the minimum WSL version recorded in the audit, must tell the user when `wsl --shutdown` is required to take effect, and must have real translations in all nine locales. Reuse the existing patterns: `settingSwitch` / `settingText` in `lib/dialogs/settings_dialog.dart` for `wsl.conf`, and the `_settings` controller map plus its toggle/combo/size/file-picker renderers in `lib/screens/settings_screen.dart` for `.wslconfig`. Do not invent a second settings mechanism.

## Tasks

- [ ] Implement every **S**-sized `.wslconfig` finding in `lib/screens/settings_screen.dart`:
  - Add each missing key with the correct widget type (toggle for booleans, combo box with the documented enum values, size field with postfix, file picker for paths)
  - Correct any key whose widget type or default the audit marked wrong
  - Update tooltips whose text the audit marked outdated, using current documentation wording
  - Make sure the clear/reset path (`_settings` clearing and the known-keys list around line 299) includes every new key so stale values cannot survive

- [ ] Implement every **S**-sized `wsl.conf` finding in `lib/dialogs/settings_dialog.dart`:
  - Add the missing sections and keys (`[network]` hostname/generateHosts/generateResolvConf, `[interop]` enabled/appendWindowsPath, `[user]` default, `[boot]` command, and anything else the audit lists)
  - Extend the "clear known wsl.conf settings" list (around line 400) with every new `section-key` pair so switching distros cannot leak values between them
  - Verify round-tripping through `getWslConf`/`setWslConf` in `lib/api/wsl.dart` for each new key, including values containing spaces and `=`

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
