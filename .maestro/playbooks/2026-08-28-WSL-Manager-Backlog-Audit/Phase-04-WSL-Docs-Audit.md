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

- [x] Classify and prioritise every finding in `doc/audit/wsl-docs/index.md`:
  - Size each as **S** (a key added to an existing editor: label, tooltip, widget, i18n keys), **M** (a new section or dialog), or **L** (a new screen or subsystem)
  - Rank by user impact, noting which findings map to known user complaints or open issues
  - Produce an explicit ordered implementation list — this list is the input to Phase 05, so it must be complete and unambiguous

  **Result (2026-08-28):** `index.md` grew six sections — sizing rubric, ranking rubric,
  issue-evidence table, finding registry, the ordered list, "not scheduled", and the i18n
  key inventory. **24 items, P05-01 … P05-24: 17 S · 6 M · 1 L**, plus one research item
  (`R-A`) and **eleven findings explicitly not scheduled, each with a reason**, so the list
  is closed rather than merely long. Every finding in all six audit files has a destination;
  the registry is per-file so a Phase 05 reader can go finding → item or item → finding.

  **The ranking is no longer this audit's opinion.** The brief asked for a mapping to known
  complaints, and every prior task recorded that it had not been done. I read all **183**
  `bostrot/wsl2-distro-manager` issues (open and closed) and matched them against the
  findings — **20 issues map, nine of them still open, and every tier-0 and tier-1 item now
  has at least one report behind it.** The severity judgements the code-only passes made
  survive contact with the tracker. Marked **direct** / **plausible** / **adjacent** so
  Phase 05 cannot overclaim:

  1. **#280 (`move` deleted my distro) is the only finding in this audit with a user report
     of real data loss.** It maps exactly to `cli-flags` CC-2 — `move()` is export →
     unregister → import, and the reporter fell into the window between steps 2 and 3. That
     reorders the list: P05-15 is **tier 0 by impact** but depends on P05-08, so it is
     scheduled after it with an explicit escape hatch — if Phase 05 runs short, ship the
     S-sized confirmation dialog #280 itself asked for, which needs nothing from P05-08.
  2. **#185's reporter published the fix for `wsl.conf` CC-1/CC-2 in their own bug report.**
     Their workaround, `echo -e "[network]\nhostname=…" >> /etc/wsl.conf`, is the writer's
     third branch — the only one of the three that is not `sed`. Two independent reports of
     that writer (#185, #309 — still open), and #309 shows the *call site* was fixed in
     June 2026 while the writer under it was not.
  3. **#225/#234 are a user reading WSL's stderr for us.** They reported
     `Unknown key 'wsl2.pageReporting'` on every WSL start, caused by the app offering a key
     Microsoft had removed. That is the same diagnostic channel `runtime` R-4 found silently
     rejecting relocated `[experimental]` keys today — so the app has already shipped this
     exact failure once, and the orphaned `unusedmemoryinfo-text` string is what remains of it.
  4. **`[user] default` (`wsl.conf` CC-6) is the best-evidenced gap after the move** — three
     reports (#268, #313 both open, #192), and #313 adds a mechanism the audit did not have:
     the prefs outlive the distro, so a recreated distro of the same name inherits a deleted
     user. P05-05 now owns that lifecycle, not just the missing widget.
  5. **#300 is a candidate for CC-9, not proof.** "点击设置闪退" — the app exits the moment
     Settings is clicked — is exactly CC-9's symptom, but the report carries no `.wslconfig`,
     no environment and no repro. Recorded as **plausible**, and P05-01's first step is the
     reproduction that would settle it. That reproduction is also the one thing `verification`
     and `runtime` both left undone, so it is now the top of the list.

  Two sizing decisions Phase 05 should not re-litigate:

  - **The brief's rubric has no bucket for the two worst findings.** S/M/L is written around
    UI surfaces ("a key", "a dialog", "a screen"), and the `.wslconfig` engine and the
    `wsl.conf` writer are neither — they are rewrites of existing read/write paths. I
    extended **M** to cover "a rewrite that needs its own tests" and stated the extension in
    the rubric, so nobody reads their **M** as "go build a dialog".
  - **P05-02 and P05-03 are scheduled above almost every key-level item**, which looks like
    an impact inversion and is not: adding a combo box or a missing key to an editor whose
    writer corrupts what it writes just ships a nicer way to lose data. Conversely **P05-08,
    the "enabling" item, sits at position 8, not 1** — nothing in tiers 0–1 needs a version
    check; everything from P05-15 on does.

  Also produced, because the phase's last task needs it as input: a per-item i18n inventory
  — roughly **45 new keys and 18 rewrites** across nine locales, with names checked against
  the 284 keys already in `en.json` so `wsldefaultuser-text`, `stopwsl-text`,
  `selectfile-text`, `move-text` and `size-text` get reused rather than duplicated.

  Corrections applied back into the area files (no source file touched): `features.md` and
  `verification.md`'s "no issue was consulted" caveats now point at the evidence table;
  `wslconfig-keys.md` CC-9, `wslconf-keys.md` CC-1/CC-6 and `cli-flags.md` CC-2 carry their
  reports inline. **Nothing was withdrawn or downgraded.**

  Not done here, deliberately: the false-negative sweep (the next task owns re-reading both
  editors end to end, and it may still add findings — the ordered list says so rather than
  presenting itself as final), and no i18n key was actually written.

- [x] Sanity-check the audit for false negatives before declaring it done:
  - Re-read `lib/screens/settings_screen.dart` and `lib/dialogs/settings_dialog.dart` end to end and confirm every key they render appears in the audit tables with a verdict
  - Confirm every `wsl.exe` invocation in `lib/api/wsl.dart` appears in `cli-flags.md`
  - Add a short "what was not examined" section rather than implying full coverage where none was checked

  **Result (2026-08-28):** New seventh audit file, `doc/audit/wsl-docs/coverage-sweep.md`.
  All three source files were read in full (1253 + 492 + 1857 lines) and enumerated from
  the *source* first, then looked up in the audit — the sweep checks the audit's silences,
  not its claims, which is the one direction `verification` and `runtime` could not run.

  **The inventories held. 27/27 `.wslconfig` keys, 11/11 `wsl.conf` keys and 27/27
  `wsl.exe` invocation sites already had a verdict**, and every per-key line reference in
  both key tables re-checked exact. No documented key and no `wsl.exe` flag was found
  missing from a table. The audit's headline counts are a floor as well as a ceiling now.

  Four findings were added, all at the *edges* of those tables — which is where a per-key
  diff structurally cannot look:

  1. **S-1 — the missing `[user] default` is shadowed, not merely absent.** The distro
     dialog renders a **Start user** box (`settings_dialog.dart:134-140`) tooltipped
     `wsldefaultuser-text` — the app's own "default user" string — directly above the
     `wsl.conf` expanders. It only sets `--user` on terminals *this app* launches
     (`wsl.dart:393`), so it does not change the distro's default user, does not apply to
     `wsl` typed anywhere else, and does not travel with an export. That is exactly the
     symptom #268 reports. `wsl.conf` CC-6's verdict is unchanged; its impact is higher,
     and P05-05 now has to place the real editor *next to* this box and label both, rather
     than adding a second user field to the same dialog.
  2. **S-2 — no `.wslconfig` key can ever be removed from the app** (new `wslconfig-keys`
     CC-11). `saveSettings` writes only non-empty controllers (`:311`) and `setConfig` has
     three branches and no delete. Clearing a box does nothing. The documented default
     system is "absent key = default", so the app cannot express the most ordinary request
     a settings screen gets. **This blocks P05-04**: the prescribed tri-state has nowhere
     to write "unset" until P05-02 lands, so the ordered list now carries that dependency
     explicitly.
  3. **S-3 — `setConfig`'s regexes are unanchored** (`RegExp('$key[ ]*=')`, `multiLine`,
     no `^`). Against `#memory=8GB` a write to `memory` substitutes *inside the comment*:
     the line stays commented, WSL still ignores it, the app reports the save as done.
     `wslconfig-keys` CC-5 had only the read half of the comment problem.
  4. **S-4** — `Default Distro Location` / `General Data Location` share the `_settings`
     map with the config keys and had no row anywhere; recorded with verdict `n/a` so the
     coverage claim is complete rather than silent.

  **And one finding was withdrawn**, which is the same sweep run backwards and the reason
  it is not just an additive pass: the "prefs outlive the distro" mechanism the
  classification pass attached to #313 is **already fixed in this tree** —
  `clearDistroPrefs` (`helpers.dart:388`) is called from `WSLApi.remove` (`wsl.dart:951`)
  and wipes all eleven per-distro prefixes on unregister, and `loadDistroSettings` clears
  its twelve `wsl.conf` `knownKeys` on every dialog open. **P05-05 is smaller than it was
  scheduled**: the missing editor and nothing else. Phase 05 should re-test #313, not
  reimplement it.

  Three stale citations fixed, no verdict affected: `settings_screen.dart:1196` → `:1197`
  (CC-9's parse), and `--user` in `execCmds` is `wsl.dart:994`, not `:1017` — its two
  sibling spawns (`runCmds:1051`, `startShell:1118`) were uncited and now are.

  Every item count in `index.md` is unchanged — the additions fold into P05-02 and P05-05
  — so the ordered list stays 24 items, and what changed is how much weight it can carry.

  `coverage-sweep.md` ends with its own *What was not examined*, and it is the honest
  limit on this whole phase: the app was still never launched; only the two editors and
  `wsl.dart` were read end to end (`create_dialog.dart`, `list_item.dart`,
  `docker_images.dart`, `copy_dialog.dart` were grepped for specific keys, not swept); the
  sweep re-checks the *app* side against the existing inventories and does **not** re-read
  the docs clone, so a documented key the first pass missed would still be invisible; and
  S-2 and S-3 are read from source, not reproduced. `index.md`'s *Coverage limits* now
  points at that section before its own.

  No source file was touched — this task is documentation only.

- [x] Add the new i18n keys required by the S-sized findings to every file in `lib/i18n/` by appending (never sorting), with real translations for de, en, es, hu, ja, pt, tr, zh_CN and zh_TW, so Phase 05 can wire up UI without a translation detour. Run `dart scripts/check_translations.dart` (or the equivalent script in `scripts/`) and `flutter test test/locales_test.dart` to confirm the locale set stays consistent.

  **Result (2026-08-28):** **46 new keys × 9 locales = 414 strings appended**, every one
  hand-written per locale rather than copied from English. The classification pass
  estimated "roughly 45"; the extra one is the eleventh `wsl.conf` label/description pair
  (`bootcommand-text`), which its per-item table folded into the P05-13 count without
  naming.

  Scope taken literally: the task says **add the new keys**. The inventory's **18
  rewrites** (P05-12's 17 `*info-text` strings, P05-07's `globalconfigurationinfo-text`),
  the **one deletion** (`unusedmemoryinfo-text`) and the **one rename**
  (`wslsettings-text`) all change strings the app renders *today*, so they belong with the
  UI change that motivates them — P05-12, P05-07 and P05-22 — not here. Nothing existing
  was touched; the diff is 47 added lines and 1 changed line (the trailing comma) per
  locale file.

  What went in, by item:

  | Item | Keys | n |
  |:---|:---|---:|
  | P05-04 | `settingdefault-text`, `settingunset-text` | 2 |
  | P05-05 | `defaultuserinfo-text` — and it names the trap: it states that this is the *distro's* default user, unlike the Start user box above it, which only affects launches from this app | 1 |
  | P05-06 | `wslconfrestart-text`, `terminatedistro-text` | 2 |
  | P05-07 | `restartwslnow-text`, `restartwslprompt-text` | 2 |
  | P05-09 | `deprecatedvalue-text` | 1 |
  | P05-10 | `onlyapplieswhen-text` (`%s`), `ignoredinmirrored-text` | 2 |
  | P05-11 | `milliseconds-text`, `unitexample-text` | 2 |
  | P05-13 | 11 label + 11 description pairs for the `wsl.conf` keys | 22 |
  | P05-14 | `gpu-text` / `time-text` / `user-text` section headers + 3 label/description pairs | 9 |
  | P05-19 | `setdefaultdistro-text`, `setwslversion-text` | 2 |
  | P05-22 | `microsoftwslsettings-text` | 1 |

  Reuse held: `wsldefaultuser-text`, `stopwsl-text`, `selectfile-text`, `move-text` and
  `size-text` were left alone, and all 46 names were checked against the 284 existing
  keys before writing — zero collisions. `mountoptions-text` already exists for the *disk
  mount* dialog, so the `wsl.conf` one is `automountoptions-text`, deliberately not a
  reuse: they are different settings with different value grammars.

  Two descriptions were written **from behaviour, not from upstream prose**, as
  [[wslconf-keys]] instructed:

  1. **`protectbinfmtinfo-text`** — the documented sentence describes the `false` case and
     would mislead as a tooltip. The key says what `true` (the default) does: WSL keeps
     its own binfmt registration for Windows interop and systemd cannot replace it.
  2. **`automountoptionsinfo-text`** — carries the `metadata` precondition the docs state
     and the app never did (`umask`, `fmask`, `dmask` are inert without it), plus a
     worked example. That is the guidance behind the #224-class confusion.

  Mechanism: `Working/new-i18n-keys.json` holds the nine locale blocks;
  `Working/append_i18n_keys.dart` appends them textually — it finds the closing brace,
  re-serialises nothing, and preserves each file's CRLF endings, so the existing 284
  entries keep their byte-for-byte formatting and their order. Re-running is a no-op.
  This is what "appending (never sorting)" needs: `scripts/add_translation_key.dart`
  round-trips the whole map through `JsonEncoder`, which would have reformatted every
  file, and it fills gaps with the **English string** — the exact failure this task exists
  to avoid.

  **Verification:**

  - `dart scripts/check_translations.dart` — clean, no missing keys in any locale.
  - `flutter test test/locales_test.dart` — **7 tests pass** (4 existing + 3 added).
  - `flutter test` — **393 tests pass**, no regressions.
  - `flutter analyze test/locales_test.dart` — no issues.

  Three tests added to `test/locales_test.dart`, in its existing "explain why the
  invariant matters" style:

  - **placeholder parity** — every locale must use as many `%s` / `%sN` as English, for
    every key. A translation that drops one loses the value it was meant to show; one that
    invents one renders a raw `%s`. Counts only, because the localization package
    (`localization-2.1.1`, `localization_service.dart:154-171`) fills `%s` positionally
    and `%sN` by index, so `%s` and `%s0` are interchangeable for a single argument.
  - **the 46 audit keys are present and non-empty in every locale.**
  - **the 46 audit keys are not verbatim English** in the eight non-English locales,
    skipping values of 20 characters or less so `gpu-text` ("GPU" everywhere) and de's
    `networkhostname-text` ("Hostname") do not read as failures. This is the one that
    actually pins the work: an English fallback is one careless
    `add_translation_key.dart` run away.

  **Two things found while measuring, neither in scope, both worth Phase 05 knowing:**

  1. **`zh_CN`'s `cleanuptitle-text` uses `%s` where the other eight use `%s0`** — checked
     against the package and the call site (`list_item.dart:351`, one argument), and it is
     **correct**, not a bug: `%s` and `%s0` both resolve to `arguments[0]`. Recorded
     because the parity test had to be written around it, and because it looks like a
     defect at a glance.
  2. **A pre-existing English-fallback backlog of ~7 long strings per locale** —
     `nodisksfound-text`, `unmountfailed-msg`, `usbdetected-msg`, `mountoptionshint-text`,
     `diskofflinehint-text`, `unknownmounterror-text`, `exampleunmountpath-text` in es,
     hu, ja, pt, tr and zh_TW, plus `consoleinfo-text` in hu. All from the disk-mount
     feature, all untouched here. This is why the third test is scoped to the audit's own
     keys rather than the whole file: a global rule would fail on debt this task did not
     create and was not asked to pay down. Worth a task of its own.

  Not done here: no UI code was wired up. Every key is unreferenced until Phase 05 renders
  it, which is the point — the translation detour is now paid in advance.
