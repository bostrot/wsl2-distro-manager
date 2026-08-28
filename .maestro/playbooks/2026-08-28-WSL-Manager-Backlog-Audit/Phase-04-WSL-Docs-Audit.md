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
     these three is **outdated**, not merely stale wording.
     *(Corrected by the runtime task: this point originally ended "— a user following it
     writes a section header current WSL ignores." WSL 2.6.3.0 accepts those keys under
     **either** section, proven behaviourally. See `runtime.md` R-5. The contradiction is
     real; the consequence is a file that disagrees with the docs, not a dead setting.)*
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

- [x] Diff each inventory against the app and write per-area findings under `doc/audit/wsl-docs/`, one file per area, each with YAML front matter (`type: analysis`, `title`, `created: 2026-08-28`, `tags: [wsl, docs-audit, <area>]`, `related:` wiki-links) and a table of key → documented → app state → verdict:
  - `wslconfig-keys.md` — global `.wslconfig` coverage
  - `wslconf-keys.md` — per-distro `wsl.conf` coverage
  - `cli-flags.md` — `wsl.exe` flags the app shells out to versus those documented
  - `features.md` — whole feature surfaces (mirrored networking, DNS tunneling, sparse VHD, `--manage`, the WSL Settings app, systemd defaults, plugins, custom distro `.wslconfig`-based distribution)
  - Cross-link them all from `doc/audit/wsl-docs/index.md` using `[[wslconfig-keys]]`-style wiki-links

  **Result (2026-08-28):** Five files written under `doc/audit/wsl-docs/` —
  `index.md`, `wslconfig-keys.md`, `wslconf-keys.md`, `cli-flags.md`, `features.md`.
  All five carry `type: analysis` front matter and the four `[[wiki-link]]` targets
  resolve. Verdict vocabulary is fixed in `index.md`:
  `covered` / `outdated` / `wrong` / `missing`.

  **The headline contradicts this phase's brief, and that is the main result.**

  1. **`.wslconfig` key coverage is complete — 27 of 27.** All 20 `[wsl2]` and all 7
     `[experimental]` reference-table keys are rendered by
     `settings_screen.dart:1010-1156`. Verified by grepping **both** the camelCase and
     the all-lowercase spelling of every key (the case-insensitivity trap the previous
     task flagged); each resolves to exactly one `settingsWidget(...)` call site. The
     brief's orientation paragraph undercounted the app — `safeMode`, `debugConsole`,
     `maxCrashDumpCount`, `dnsProxy`, `firewall`, `defaultVhdSize`,
     `bestEffortDnsParsing`, `initialAutoProxyTimeout`, `ignoredPorts` and
     `hostAddressLoopback` are all already there. **There is no missing-key finding in
     this area.** Phase 05 should not budget for one.
  2. **`wsl.conf` is 11 of 15.** Missing: `[user] default`, `[boot] protectBinfmt`,
     `[gpu] enabled`, `[time] useWindowsTimezone`. The brief undercounted here too —
     `boot.command`, `network.*` (3) and `interop.*` (2) are already exposed.
  3. **`wsl.exe`: 13 of 30 top-level verbs used.**

  Two writer defects found that are more serious than any missing key, and both are
  code bugs rather than docs gaps — Phase 05 should treat them as fixes, not features:

  - **`assets/scripts/settings.bash` is section-blind.** Its `sed` runs over the whole
    file with `/g`, and `[automount] enabled` and `[interop] enabled` are *both* exposed
    by the dialog. Toggling either rewrites both. Same script breaks outright on any
    value containing `/` — `sed -i 's/root[ ]*=[ ]*.*/root = /mnt//g'` — which is the
    documented default of `automount.root` and the shape of every plausible
    `boot.command`. `setSetting` returns `true` unconditionally and `execCmds` runs with
    `showOutput: false`, so the failure never reaches the user, and the value is still
    written to prefs — the dialog shows the change as applied when it was not.
  - **`WSLApi.setConfig` / `readConfig` (`wsl.dart:544-630`)** are section-blind,
    case-sensitive against a case-insensitive format, and `readConfig` strips *every*
    space inside a value — so `kernelCommandLine = console=ttyS0 nokaslr` reloads
    mangled and is written back mangled on the next Save. The correct sectioned parser
    already exists in the same file (`getWSLConf`, `:1824`); only the write paths are wrong.

  Third systemic finding: **13 boolean toggles across both editors render `false` for
  keys the docs default to `true`** (7 in `.wslconfig`, 6 in `wsl.conf`), because both
  read an absent key as off. And **the whole `wsl.conf` dialog has no descriptions and
  no `.i18n()` calls** — labels are `setting.uppercaseFirst()`, so `"MountFsTab"`.

  Two corrections to the brief's own framing, recorded in the files:

  - **There is no WSL Settings app page** (already flagged by task 1). `features.md` F-5
    records it as an *open question*, not a resolved finding, and explicitly says not to
    cite `wsl-config.md` for a WSL Settings claim.
  - **`networkingMode` is a five-value enum**, not `NAT | mirrored`. `features.md` F-1
    and `wslconfig-keys.md` both carry the full list plus the `bridged` deprecation.

  Deliberately **not** done here, because later tasks own them: no `wsl` command was
  executed (runtime task), no sizing or ranking (classification task), and no i18n keys
  were added. `index.md` carries a status table saying so, so nobody mistakes this for a
  prioritised backlog.

- [x] Verify each claimed gap against the code before recording it as missing — do not trust the key list alone:
  - `grep -rn "<key>" lib/` for every key marked missing, including camelCase and lowercase spellings
  - For keys the app does expose, check the *widget type* is right: booleans rendered as toggles, enums as combo boxes with the documented values (e.g. `networkingMode` = `NAT` | `mirrored`, `autoMemoryReclaim` = `disabled` | `gradual` | `dropcache`), sizes with the size postfix, and paths with a file picker
  - Check the tooltip/help text matches current documentation, not a 2023 snapshot; flag outdated wording as `outdated` rather than `covered`

  **Result (2026-08-28):** Second pass written to `doc/audit/wsl-docs/verification.md`
  and corrections applied in place to the four area files + `index.md`. **No claim was
  withdrawn — every gap the previous task recorded is real.** But 3 verdicts were wrong in
  the safe direction and 8 findings were missed. No source file was touched.

  **The largest result is a crash, and it came out of the widget-type check, not the key
  list.** `fluent_ui` 4.13.0's `Slider` asserts its range in the *constructor*
  (`slider.dart:41`), and `settings_screen.dart:1196` feeds it a value parsed straight from
  `.wslconfig` with no clamp. `wsl-config.md:252` says `size` entries **default to bytes**,
  so `memory=8589934592` is the documented way to write 8 GB — it parses cleanly to
  `8589934592.0` and is handed to a slider whose `max` is `hostGB + 1`. The Settings page
  throws on build. `processors=64` on a 16-thread host does the same. Asserts are stripped
  in release, so the shipped app draws the thumb off the track instead of crashing — the
  failure mode differs by build mode, which is why nobody has reported it. Recorded as
  `wslconfig-keys.md` **CC-9**; it should be the first thing the runtime task reproduces,
  since it is a one-line file edit plus an app launch.

  Verdicts corrected, all three from `covered`/`outdated` to something worse:

  1. **`guiApplications` → `wrong`.** Its tooltip ends "Only available for Windows 11."
     The docs put **no** ¹ footnote on that key — the marker sits on `debugConsole`,
     `nestedVirtualization`, `vmIdleTimeout` and `autoProxy`. A Windows 10 user reading the
     app skips a key that works on their machine.
  2. **`safeMode` → `outdated`.** `safemodeinfo-text` is truncated mid-sentence and drops
     "Only available for Windows 11 and WSL version 0.66.2+" — the *only* inline WSL-version
     floor in the entire `[wsl2]` reference table, and the app is the one place that loses it.
  3. **`processors` → `outdated`.** Tooltip drops "logical" from "How many logical
     processors", and the slider is a CC-9 site.

  Five further findings the first pass did not have:

  4. **The `ComboBox` the enum keys need is already used three times in this app** —
     `create_dialog.dart:522`, `mount_dialog.dart:334` and `:515`. Adding
     `SettingsType.enumeration` reuses an established pattern, so the classification task
     should size `networkingMode` and `autoMemoryReclaim` as **S**, not **M**.
  5. **Case-sensitivity (CC-4) is worse than "the setting is ignored."** Traced end to end:
     a lowercase `swapfile=` line makes `readData` create a controller with no widget, so the
     `swapFile` box renders **empty** — the screen shows nothing configured — and once the
     user fills it, Save writes a *second* line, leaving `swapfile` and `swapFile` both under
     `[wsl2]`.
  6. **`wsl.conf` text values reach a root shell unescaped.** `setSetting`'s
     `replaceAll('VALUE', value)` lands inside `echo -e "…"` and `execCmds` runs with
     `-u root`, so a `"` or `$(…)` in `boot.command` / `automount.options` executes as root in
     the distro. Not remotely triggerable, but it constrains the Phase 05 fix: the writer must
     **escape**, not just change the `sed` delimiter. Recorded as `wslconf-keys.md` CC-7.
  7. **"WSL Settings" is already this app's name for the `wsl.conf` dialog**
     (`en.json:134` → `settings_dialog.dart:291`), while Windows now ships a Start-menu app
     of that exact name editing `.wslconfig` — which this app edits on a *different* screen.
     F-5 amended: the collision has to be renamed before anything else there, which makes F-5
     cheaper and more urgent than the first pass judged.
  8. **Re-grep footnote for `cli-flags.md` CC-1.** `grep -rn -- "--version" lib/` returns
     **1** and `--format` returns **2**, so a later reader will think the "0 hits" claim is
     refuted. It is not — those are `cloudflared --version` and two `docker --format` calls.
     Footnoted in place so the claim survives.

  Full tooltip diff (all 27 keys, app string against the doc sentence it paraphrases) is in
  `verification.md` Part 3: **10 covered, 16 outdated, 1 wrong**; only 8 are
  verbatim-complete. The dominant failure is silent truncation of the docs' "Only applicable
  when…" clauses — the same conditions `wslconfig-keys.md` CC-6 says no widget enforces. They
  are absent from both the behaviour *and* the text, so a user has no way to learn them.
  Also confirmed: `globalconfigurationinfo-text` misquotes its own source, "take **affect**"
  where the doc says "take effect".

  Still not run: nothing was executed. CC-9 is derived from the `fluent_ui` source and the
  parse expression, and only `en.json` was diffed — the other eight locales may carry
  different errors, which the i18n task at the end of this phase should check for the three
  corrected strings.

- [x] Verify the runtime behaviour claims the app makes, against the local WSL version:
  - Run `wsl --version` and record kernel/WSLg/MSRDC versions in the audit
  - Confirm which documented keys the installed WSL actually honours (some are gated by version); annotate each finding with its minimum WSL version so Phase 05 can gate the UI correctly
  - Note where the docs require `wsl --shutdown` for a key to take effect, and whether the app tells the user that

  **Result (2026-08-28):** Third pass written to `doc/audit/wsl-docs/runtime.md` (findings
  R-1—R-13) and its corrections applied in place to `index.md` and all four area files.
  Measured against **WSL 2.6.3.0** / kernel 6.6.87.2-1 / WSLg 1.0.71 / MSRDC 1.2.6353 /
  Windows 10.0.26200.9168; host 10 logical CPUs, 7.98 GiB RAM. No `lib/` file was touched.

  **The technique is the reusable part.** WSL 2.6.3 reports `.wslconfig` problems on
  **stderr with file and line number**, before the VM boots, and `WSL_UTF8=1` makes that
  output UTF-8 instead of UTF-16LE. Four diagnostics turned out to be usable oracles
  (unknown key / invalid key name / duplicate key / invalid size string), so "does this
  build honour key X in section Y" is a one-shutdown question rather than a guess. Ten
  probe `.wslconfig` files are kept in `Working/runtime/`. `%UserProfile%\.wslconfig` was
  empty (`md5 d41d8cd9…`), was backed up, and was restored byte-identical — hash
  re-verified. `ai-workspace`'s `/etc/wsl.conf` was backed up in-distro and moved back;
  both distros are `Stopped`, as they were at the start.

  Answers to the three bullets, in order:

  1. **Versions recorded** in `runtime.md` “The machine under test”. Every documented floor
     (Build 19041, Win 11 ¹, Win 11 22H2 ², WSL 0.66.2 / 0.67.6 / 2.0.9 / 2.3.25 / 2.4.5)
     is met here, so **no key is version-gated out on this machine** — which is what makes
     every “unrecognised key” result below about *section placement*, never about age.
  2. **All 27 reference-table keys are recognised**, plus both Intune-only keys
     (`systemDistro`, `kernelDebugPort`), confirming the inventory's “29 known keys”. And
     **all 12 flags `cli-flags.md` marks H are present in 2.6.3's `--help`** — the H mark
     is about incomplete docs, not preview gating, so Phase 05 needs one coarse “is this
     2.x” check, not per-flag guards.
  3. **The restart rule is real, silent, and scoped differently per file.** With the VM
     running, a rewritten `.wslconfig` had no effect and printed no warning until
     `wsl --shutdown`; a `wsl.conf` change likewise did nothing until
     `wsl --terminate <distro>` — **no global shutdown needed**, so the dialog's fix is
     cheaper than the settings screen's. The app *does* tell the user for `.wslconfig`
     (`globalconfigurationinfo-text`, present in all nine locales, rendered at
     `settings_screen.dart:1017`) and says **nothing** for `wsl.conf`.

  **One earlier claim is withdrawn, and it is the most important thing here.**
  `Working/wslconfig-keys.md:132` said a user following `troubleshooting.md` writes
  `[experimental] networkingMode=mirrored` “which the current WSL ignores.” **False.**
  WSL 2.6.3 accepts `networkingMode`, `firewall`, `dnsTunneling` and `autoProxy` under
  *either* section — proven behaviourally, not just by silence: `[wsl2]` and
  `[experimental]` spellings both moved `eth0` from `172.26.21.255/20` (NAT) to the host's
  LAN address `192.168.3.82/24`. Those four are the **only** keys with dual-section
  acceptance; every other misplaced key in the same probe was rejected. The docs
  contradiction stands, but Phase 05 must not size an item on the ignored-setting claim.
  Corrected in `Working/wslconfig-keys.md` and at `features.md` F-1/F-2.

  **Three findings escalate from “untidy” to “data-affecting”:**

  - **CC-3 (section-blind writer).** All seven `[experimental]` keys are *rejected* under
    `[wsl2]`, and `memory` is rejected under `[experimental]`; `wsl.exe` still exits 0 and
    boots with the key **unset**. So `saveSettings` relocating a user's hand-added
    `[experimental]` key doesn't tidy the file — it turns the setting off.
  - **CC-4 / V-5 (case-sensitivity).** WSL detects the duplicate the app creates and
    resolves it to the **first** occurrence (measured with two `memory` lines; the earlier
    won). The line the app appends is the loser — the user's edit is a silent no-op, not a
    messy file.
  - **CC-9 (slider crash).** Precondition verified: `memory=8589934592` is accepted by WSL
    *silently* (`MemTotal` 8 111 836 kB), so the app crashes on a value WSL is happy with.
    `processors=64` is the mirror image — WSL rejects it with a clear message and clamps to
    10; the app, reading the file rather than WSL's effective value, still asserts. The app
    is less robust than the tool it configures, in both directions.

  **Two genuinely new findings**, neither of which the code-only passes could have reached:

  - **CC-10 (new) — the app writes unescaped Windows paths and WSL discards the line.**
    `swapFile=C:\Temp\x.vhdx` is a hard parse error (`Ungültiges Escapezeichen: „T“`);
    `C:\\Temp\\x.vhdx` parses. The app escapes nothing anywhere, and the worst offender is
    the surface with the nicest UI: `kernelModules`' file picker
    (`settings_screen.dart:1025-1038`) assigns `result.files.single.path!` verbatim, so
    **every value that picker can produce** is a line WSL throws away. `kernel` and
    `swapFile` invite the same by hand.
  - **R-1 — one gate is hardware, not version.** `nestedVirtualization` defaults to `true`
    and this host's CPU refuses it, printing a warning on *every* VM start that
    `wsl-config.md` never mentions and no version check can predict. Consequence for F-9:
    reading WSL's **stderr** is worth as much as reading its version, and costs the same
    plumbing.

  Two smaller runtime facts Phase 05 needs: `#` is the only comment character `.wslconfig`
  accepts (`;` is `Ungültiger Schlüsselname`), which bounds the CC-5 fix; and `memory=6144MB`
  really is honoured (`MemTotal` 6 067 928 kB), so the 5 GB the slider's `replaceAll('GB','')`
  silently discards is memory the user actually had.

  **Still not run: the app itself.** CC-9's crash remains derived from `fluent_ui`'s
  constructor assert plus the parse expression — this pass confirms WSL accepts the
  triggering value but never opened the Settings page. `assets/scripts/settings.bash` was
  also not executed, so `wslconf-keys.md` CC-1/CC-2 are still code-read only. Everything
  measured here is one machine, one build, de-DE locale; `runtime.md`'s “what was not
  examined” section states the limits.

- [ ] Classify and prioritise every finding in `doc/audit/wsl-docs/index.md`:
  - Size each as **S** (a key added to an existing editor: label, tooltip, widget, i18n keys), **M** (a new section or dialog), or **L** (a new screen or subsystem)
  - Rank by user impact, noting which findings map to known user complaints or open issues
  - Produce an explicit ordered implementation list — this list is the input to Phase 05, so it must be complete and unambiguous

- [ ] Sanity-check the audit for false negatives before declaring it done:
  - Re-read `lib/screens/settings_screen.dart` and `lib/dialogs/settings_dialog.dart` end to end and confirm every key they render appears in the audit tables with a verdict
  - Confirm every `wsl.exe` invocation in `lib/api/wsl.dart` appears in `cli-flags.md`
  - Add a short "what was not examined" section rather than implying full coverage where none was checked

- [ ] Add the new i18n keys required by the S-sized findings to every file in `lib/i18n/` by appending (never sorting), with real translations for de, en, es, hu, ja, pt, tr, zh_CN and zh_TW, so Phase 05 can wire up UI without a translation detour. Run `dart scripts/check_translations.dart` (or the equivalent script in `scripts/`) and `flutter test test/locales_test.dart` to confirm the locale set stays consistent.
