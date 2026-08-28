# Phase 04: WSL Documentation Audit — Find Every Discrepancy

This phase diffs the official Microsoft WSL documentation (`https://github.com/microsoftdocs/wsl`) against what the app actually exposes, and produces a structured, navigable audit under `doc/audit/wsl-docs/`. It is a research phase: the output is a set of Markdown findings with front matter and wiki-links, each classified as *missing*, *outdated*, *wrong* or *covered*, and each sized as a small patch to an existing editor or a larger feature surface. Phase 05 implements everything it finds. Being exhaustive here is what makes Phase 05 worth running.

What the app exposes today, for orientation: `.wslconfig` keys live in `lib/screens/settings_screen.dart` (already including `memory`, `processors`, `localhostForwarding`, `kernelCommandLine`, `guiApplications`, `nestedVirtualization`, `vmIdleTimeout`, `networkingMode`, `dnsTunneling`, `autoProxy`, `autoMemoryReclaim`, `sparseVhd`, `dnsTunnelingIpAddress`, `kernelModules`); per-distro `wsl.conf` keys live in `lib/dialogs/settings_dialog.dart` (`boot.systemd`, `automount.enabled`, `automount.mountFsTab`, `automount.root`, `automount.options`); `wsl.exe` invocations are spread across `lib/api/wsl.dart`.

## Tasks

- [x] Fetch the authoritative source material into scratch space (never into the repo tree):
  - Clone `https://github.com/microsoftdocs/wsl` into `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/wsl-docs/` (shallow clone is fine)
  - Record the cloned commit SHA and date — every finding must cite it, so the audit stays falsifiable later
  - Identify the reference pages that matter: `wsl-config.md`, `basic-commands.md`, `filesystems.md`, `networking.md`, `disk-space.md`, `systemd.md`, `wsl-plugins.md`, `use-custom-distro.md`, `build-custom-distro.md`, the WSL Settings app page, and the release-notes/changelog pages

  **Result (2026-08-28):** Cloned shallow (`--depth 1`) to
  `Working/wsl-docs/` — 37 Markdown files, 83 MB, 1 commit.
  **Citation string for every finding: `microsoftdocs/wsl@8842def (2026-07-30)`**
  (full SHA `8842def77a852af26318b9ebec78063a94b068ed`, branch `main`, subject
  "Removed workflow"). `.gitignore:72` (`.maestro/playbooks/**/Working/`) already
  excludes the path — confirmed with `git check-ignore -v`, so the nested `.git`
  does not reach the app repo's `git status`. Full provenance record, page
  inventory with `ms.date` stamps, and the caveats below:
  `Working/wsl-docs-source.md`.

  Three things the task list assumed that do not hold, found while identifying
  the pages — they change how the later tasks must be sourced:

  1. **There is no WSL Settings app page.** Not in the repo, not in `WSL/toc.yml`.
     The whole coverage is one callout at `wsl-config.md:216` ("It is recommended
     to modify WSL configurations directly in WSL Settings…"). The `features.md`
     finding for that surface must be researched against the shipping app or
     `microsoft/WSL`, and must say so rather than cite a page that isn't there.
  2. **Both changelog pages are dead and cannot supply the per-key minimum WSL
     version.** `release-notes.md` stops at Windows Insider Build 21364 (2021);
     `kernel-release-notes.md` stops at kernel 5.15.57.1 (2022);
     `store-release-notes.md` is a 14-line stub pointing at
     `https://github.com/microsoft/WSL/releases`. Use instead (a) the inline
     version gates in `wsl-config.md`, which annotate the modern keys in prose,
     and (b) the `microsoft/WSL` releases page for anything unannotated.
  3. **`wsl2-mount-disk.md` is the real reference for the `--mount` flag family**
     (`--vhd`, `--bare`, `--partition`, `--type`, `--options`, `--unmount`) and was
     not named in the list. Added to the primary set. Also added as secondary
     config surface to sweep: `enterprise.md` and `intune.md` (policy-controlled
     `.wslconfig`), `case-sensitivity.md` and `file-permissions.md` (automount
     `options=`), `troubleshooting.md` (the "requires `wsl --shutdown`" claims).
     23 of the 37 pages contain a `wsl --<flag>` invocation; `wsl-exe-flags.md`
     must sweep all 23, not just `basic-commands.md`.

  One discrepancy surfaced early and is parked for `wslconfig-keys.md` rather than
  resolved here: `networkingMode`'s documented values are
  `none | nat | bridged | mirrored | virtioproxy` (`wsl-config.md:242`), with
  `bridged` deprecated since WSL 2.4.5 and `virtioproxy` the NAT fallback since
  2.3.25 — not the two-value `NAT | mirrored` this phase's brief assumes.

- [x] Extract the documented surface into machine-checkable inventories in `Working/`:
  - `wslconfig-keys.md` — every `[wsl2]`, `[experimental]` and other section key, with its type, default, minimum WSL version and one-line description
  - `wslconf-keys.md` — every `wsl.conf` section/key (`[automount]`, `[network]`, `[interop]`, `[user]`, `[boot]`) with the same fields
  - `wsl-exe-flags.md` — every documented `wsl.exe` command and flag, including newer ones such as `--manage`, `--mount --vhd`, `--import --vhd`, `--export --vhd`, `--install --no-distribution`, `--version`, `--update`, `--set-sparse`, `--move`
  - Note explicitly which keys the docs mark as deprecated, experimental-graduated, or renamed

  **Result (2026-08-28):** Three inventories written, all citing
  `microsoftdocs/wsl@8842def (2026-07-30)` with page + line for every row.
  `Working/wslconfig-keys.md` (29 keys), `Working/wslconf-keys.md` (7 sections /
  15 keys + 7 `automount.options` sub-values), `Working/wsl-exe-flags.md`
  (64 commands + options, swept across all 23 pages carrying a `wsl --<flag>`).
  Each file ends with a "what was not examined" section. No `lib/` file was
  opened — this task is the documented side only.

  Six things that change how the later Phase 04 tasks must be run:

  1. **`--set-sparse` and `--move` are not in the docs at all.** Nor are
     `--shell-type`, `--`, `--distribution-id`, `--uninstall`, `--shutdown --force`,
     `--install --version/--vhd-size/--fixed-vhd/--legacy`, or
     `--manage --set-default-user` — 12 flags exist only in `wsl.exe --help`.
     I ran `wsl.exe --help` locally (de-DE output; flag spellings verbatim,
     descriptions translated) and marked those rows **H** so the absence is a
     checkable claim rather than missing evidence. `cli-flags.md` must diff the
     app against **D + H**, not against `basic-commands.md` alone.
  2. **`--export --vhd` is stale.** `basic-commands.md:185` documents it; `faq.yml:188`
     and the shipping binary use `--export --format <tar|tar.gz|tar.xz|vhd>`, and the
     local `--help` offers no `--vhd` on `--export` at all. Anything in `lib/api/wsl.dart`
     that shells out to `--export --vhd` needs re-verification, and the compressed
     export formats are an undocumented real capability.
  3. **`boot.systemd` has no row in the `[boot]` reference table** — it exists only in
     prose (`wsl-config.md:46-57`, `systemd.md`). Floor is WSL **0.67.6+**. A mechanical
     table extraction loses the most user-visible key in `wsl.conf`; the app already
     ships it, so this is a docs gap, not an app gap.
  4. **`troubleshooting.md` still calls `networkingMode`, `autoProxy` and `dnsTunneling`
     `[experimental]`** (lines 305/315/335) while `wsl-config.md` has them in `[wsl2]`.
     Same commit, contradicting itself. Any app tooltip that says "experimental" about
     these three is **outdated**, not merely stale wording — a user following it writes a
     section header current WSL ignores.
  5. **Five documented conditional dependencies** must drive UI enablement in Phase 05:
     `dnsTunneling` → {`bestEffortDnsParsing`, `dnsTunnelingIpAddress`}; `autoProxy` →
     `initialAutoProxyTimeout`; `networkingMode=mirrored` → {`ignoredPorts`,
     `hostAddressLoopback`} and **`localhostForwarding` becomes ignored**;
     `networkingMode=NAT` → `dnsProxy`. Also `automount.options`' `umask`/`fmask`/`dmask`
     are inert unless `metadata` is present.
  6. **`.wslconfig` key matching is case-insensitive and the docs use both spellings** —
     `wsl-config.md`'s example writes `swapfile=` / `localhostforwarding=` all-lowercase
     against the table's `swapFile` / `localhostForwarding`. The verification task's
     `grep -rn "<key>" lib/` must cover both spellings or it will report false gaps.

  Also recorded, for completeness rather than action: two `[wsl2]` keys
  (`systemDistro`, `kernelDebugPort`) appear only in `intune.md`, never in the reference
  table; `[automount] crossDistro` and the removed `[filesystem] umask` are historical;
  and nine upstream documentation defects (malformed `kernelModules` row, "supports four
  sections" when seven are documented, inverted `protectBinfmt` description, `--export`'s
  `-` described as stdin, duplicate `windowsterminal.profileTemplate` row, and others)
  are listed in the per-file "Documentation defects" sections.

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
