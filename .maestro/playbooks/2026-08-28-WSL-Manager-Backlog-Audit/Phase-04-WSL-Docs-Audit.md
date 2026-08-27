# Phase 04: WSL Documentation Audit — Find Every Discrepancy

This phase diffs the official Microsoft WSL documentation (`https://github.com/microsoftdocs/wsl`) against what the app actually exposes, and produces a structured, navigable audit under `doc/audit/wsl-docs/`. It is a research phase: the output is a set of Markdown findings with front matter and wiki-links, each classified as *missing*, *outdated*, *wrong* or *covered*, and each sized as a small patch to an existing editor or a larger feature surface. Phase 05 implements everything it finds. Being exhaustive here is what makes Phase 05 worth running.

What the app exposes today, for orientation: `.wslconfig` keys live in `lib/screens/settings_screen.dart` (already including `memory`, `processors`, `localhostForwarding`, `kernelCommandLine`, `guiApplications`, `nestedVirtualization`, `vmIdleTimeout`, `networkingMode`, `dnsTunneling`, `autoProxy`, `autoMemoryReclaim`, `sparseVhd`, `dnsTunnelingIpAddress`, `kernelModules`); per-distro `wsl.conf` keys live in `lib/dialogs/settings_dialog.dart` (`boot.systemd`, `automount.enabled`, `automount.mountFsTab`, `automount.root`, `automount.options`); `wsl.exe` invocations are spread across `lib/api/wsl.dart`.

## Tasks

- [ ] Fetch the authoritative source material into scratch space (never into the repo tree):
  - Clone `https://github.com/microsoftdocs/wsl` into `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/wsl-docs/` (shallow clone is fine)
  - Record the cloned commit SHA and date — every finding must cite it, so the audit stays falsifiable later
  - Identify the reference pages that matter: `wsl-config.md`, `basic-commands.md`, `filesystems.md`, `networking.md`, `disk-space.md`, `systemd.md`, `wsl-plugins.md`, `use-custom-distro.md`, `build-custom-distro.md`, the WSL Settings app page, and the release-notes/changelog pages

- [ ] Extract the documented surface into machine-checkable inventories in `Working/`:
  - `wslconfig-keys.md` — every `[wsl2]`, `[experimental]` and other section key, with its type, default, minimum WSL version and one-line description
  - `wslconf-keys.md` — every `wsl.conf` section/key (`[automount]`, `[network]`, `[interop]`, `[user]`, `[boot]`) with the same fields
  - `wsl-exe-flags.md` — every documented `wsl.exe` command and flag, including newer ones such as `--manage`, `--mount --vhd`, `--import --vhd`, `--export --vhd`, `--install --no-distribution`, `--version`, `--update`, `--set-sparse`, `--move`
  - Note explicitly which keys the docs mark as deprecated, experimental-graduated, or renamed

- [ ] Diff each inventory against the app and write per-area findings under `doc/audit/wsl-docs/`, one file per area, each with YAML front matter (`type: analysis`, `title`, `created: 2026-08-28`, `tags: [wsl, docs-audit, <area>]`, `related:` wiki-links) and a table of key → documented → app state → verdict:
  - `wslconfig-keys.md` — global `.wslconfig` coverage
  - `wslconf-keys.md` — per-distro `wsl.conf` coverage
  - `cli-flags.md` — `wsl.exe` flags the app shells out to versus those documented
  - `features.md` — whole feature surfaces (mirrored networking, DNS tunneling, sparse VHD, `--manage`, the WSL Settings app, systemd defaults, plugins, custom distro `.wslconfig`-based distribution)
  - Cross-link them all from `doc/audit/wsl-docs/index.md` using `[[wslconfig-keys]]`-style wiki-links

- [ ] Verify each claimed gap against the code before recording it as missing — do not trust the key list alone:
  - `grep -rn "<key>" lib/` for every key marked missing, including camelCase and lowercase spellings
  - For keys the app does expose, check the *widget type* is right: booleans rendered as toggles, enums as combo boxes with the documented values (e.g. `networkingMode` = `NAT` | `mirrored`, `autoMemoryReclaim` = `disabled` | `gradual` | `dropcache`), sizes with the size postfix, and paths with a file picker
  - Check the tooltip/help text matches current documentation, not a 2023 snapshot; flag outdated wording as `outdated` rather than `covered`

- [ ] Verify the runtime behaviour claims the app makes, against the local WSL version:
  - Run `wsl --version` and record kernel/WSLg/MSRDC versions in the audit
  - Confirm which documented keys the installed WSL actually honours (some are gated by version); annotate each finding with its minimum WSL version so Phase 05 can gate the UI correctly
  - Note where the docs require `wsl --shutdown` for a key to take effect, and whether the app tells the user that

- [ ] Classify and prioritise every finding in `doc/audit/wsl-docs/index.md`:
  - Size each as **S** (a key added to an existing editor: label, tooltip, widget, i18n keys), **M** (a new section or dialog), or **L** (a new screen or subsystem)
  - Rank by user impact, noting which findings map to known user complaints or open issues
  - Produce an explicit ordered implementation list — this list is the input to Phase 05, so it must be complete and unambiguous

- [ ] Sanity-check the audit for false negatives before declaring it done:
  - Re-read `lib/screens/settings_screen.dart` and `lib/dialogs/settings_dialog.dart` end to end and confirm every key they render appears in the audit tables with a verdict
  - Confirm every `wsl.exe` invocation in `lib/api/wsl.dart` appears in `cli-flags.md`
  - Add a short "what was not examined" section rather than implying full coverage where none was checked

- [ ] Add the new i18n keys required by the S-sized findings to every file in `lib/i18n/` by appending (never sorting), with real translations for de, en, es, hu, ja, pt, tr, zh_CN and zh_TW, so Phase 05 can wire up UI without a translation detour. Run `dart scripts/check_translations.dart` (or the equivalent script in `scripts/`) and `flutter test test/locales_test.dart` to confirm the locale set stays consistent.
