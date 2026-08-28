---
type: analysis
title: 'WSL Documentation Audit — index'
created: 2026-08-28
tags:
  - wsl
  - docs-audit
  - index
related:
  - '[[wslconfig-keys]]'
  - '[[wslconf-keys]]'
  - '[[cli-flags]]'
  - '[[features]]'
  - '[[verification]]'
  - '[[runtime]]'
  - '[[coverage-sweep]]'
---

# WSL documentation audit

A diff of the official Microsoft WSL documentation against what WSL Distro Manager
actually exposes. Every finding cites **`microsoftdocs/wsl@8842def (2026-07-30)`** (full
SHA `8842def77a852af26318b9ebec78063a94b068ed`, branch `main`) so it stays falsifiable
when the docs move.

## The four areas

| Area | Scope | Documented | Exposed | Missing | Re-verified |
|:---|:---|---:|---:|---:|:---|
| [[wslconfig-keys]] | global `%UserProfile%\.wslconfig` | 27 reference-table keys | **27** | 0 | 3 verdicts corrected |
| [[wslconf-keys]] | per-distro `/etc/wsl.conf` | 15 keys / 7 sections | 11 | **4** | confirmed as written |
| [[cli-flags]] | `wsl.exe` commands and options | 30 top-level verbs (64 incl. options) | 13 | 17 | confirmed; one grep footnoted |
| [[features]] | whole capability surfaces | 11 assessed | 0 fully | **7** (+4 partial) | F-5 amended |

Sweep totals from [[coverage-sweep]], which enumerated the app side rather than the docs
side: **27 / 27** `.wslconfig` keys, **11 / 11** `wsl.conf` keys and **27 / 27** `wsl.exe`
invocation sites in `lib/api/wsl.dart` resolve to a row above. Nothing the app renders or
invokes is missing a verdict.

[[runtime]] is the third pass: it executes WSL **2.6.3.0** and measures what the installed
build actually does, so the version floors, the section-placement arguments and the
"changes need a restart" claims stop being inferences. It withdraws one claim, escalates
three findings to data-affecting, and adds four new ones — the largest being that the app
writes Windows paths into `.wslconfig` with single backslashes, which WSL discards as a
parse error ([[runtime]] R-6).

[[coverage-sweep]] is the fourth and last pass, and it runs in the opposite direction to
the other three: it enumerates the app — every key the two editors render, every `wsl.exe`
invocation in `lib/api/wsl.dart` — and looks each one up in the tables, so the audit's
*silences* are checked rather than its claims. **The key and flag inventories held**: 27 / 27
`.wslconfig` keys, 11 / 11 `wsl.conf` keys and 27 / 27 invocation sites already had a
verdict. It adds four findings at the edges of those tables and **withdraws one**.

[[verification]] is the second pass over all four: every missing key re-grepped, every
widget type checked against the documented value type, every tooltip diffed string-for-string
against the doc sentence. No claim was withdrawn; 3 verdicts were corrected and 8 findings
added, the largest of which is a slider that **throws on a documented-legal `.wslconfig`
value** ([[wslconfig-keys]] CC-9).

## What the audit actually found

The headline is not what the brief anticipated. **`.wslconfig` key coverage is complete** —
all 20 `[wsl2]` and all 7 `[experimental]` keys are rendered, verified by grepping both
the camelCase and the all-lowercase spelling of each (`.wslconfig` matching is
case-insensitive, and the docs' own example file uses lowercase). There is no
missing-key finding in that area at all.

The real gaps are elsewhere, and they fall into four groups — plus one outright crash the
[[verification]] pass found while checking widget types, which outranks all of them:
`memory=8589934592` is the documented byte-form of 8 GB, and feeding it to the app's
`memory` slider trips `fluent_ui`'s range assert and throws the Settings page
([[wslconfig-keys]] CC-9).

1. **Presentation.** Two enums, two size keys and two numeric keys rendered as untyped
   free text; two path keys with no file picker; seven `.wslconfig` toggles and six
   `wsl.conf` toggles that display `false` for keys documented as defaulting to `true`;
   five documented "only applicable when…" dependencies that no widget honours; and a
   `wsl.conf` dialog with no descriptions and no localisation at all.
2. **Two config writers with real defects.** `.wslconfig` (`wsl.dart:544-592`) is
   section-blind, case-sensitive against a case-insensitive format, and strips every space
   inside a value. `wsl.conf` (`assets/scripts/settings.bash`) is section-blind in a way
   that makes `[automount] enabled` and `[interop] enabled` overwrite each other, and
   breaks outright on any value containing `/` — including `automount.root`'s documented
   default `/mnt/`.
3. **No version awareness.** Neither `wsl --version` nor `wsl --status` is called anywhere
   in `lib/`, so not one of the version floors this audit records can be enforced.
4. **Whole verbs and surfaces absent.** `wsl --manage` in its entirety (resize, move,
   set-sparse, set-default-user), `--export --format`, `--import-in-place`,
   `--set-default`, `--set-version`, custom-distro `.wsl` distribution, disk-space
   management.

## Reading order

- **[[wslconfig-keys]]** — per-key table for `[wsl2]` and `[experimental]`, plus eleven
  cross-cutting findings (CC-1 … CC-11) about the editor and the `.wslconfig` parser/writer.
- **[[wslconf-keys]]** — per-key table for all seven `wsl.conf` sections, plus seven
  cross-cutting findings, two of them data-affecting.
- **[[cli-flags]]** — every documented (**D**) and `--help`-only (**H**) `wsl.exe` command
  against every invocation in `lib/`.
- **[[features]]** — eleven whole capabilities, including the ones that are "covered" at
  key level and still unusable.
- **[[verification]]** — the second pass. Read this before quoting any verdict from the four
  files above; it is where three of them changed, and it carries the full tooltip diff
  (10 covered / 16 outdated / 1 wrong) that the per-key tables only summarise.
- **[[runtime]]** — the third pass, against WSL 2.6.3.0 on this machine. Read this before
  citing any version floor, any "WSL ignores that" claim, or any restart requirement; its
  *Corrections* table lists every earlier finding it changed.
- **[[coverage-sweep]]** — the false-negative pass. Read this if you are about to claim
  the audit is complete, or if you are implementing P05-02, P05-04 or P05-05, whose scope
  it changed.
- **This file, from *Sizing rubric* on** — the classification pass. Every finding above,
  sized and ranked, mapped to the issues that report it, and flattened into the
  *Ordered implementation list for Phase 05*. If you are implementing rather than reading,
  start there and use the area files as reference.

Supporting material, outside the repo tree, under
`.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/`:
`wsl-docs-source.md` (provenance, page inventory, `ms.date` stamps),
`wslconfig-keys.md`, `wslconf-keys.md`, `wsl-exe-flags.md` (the documented-side
inventories these four files diff against), and `runtime/` (the ten probe `.wslconfig`
files behind [[runtime]], the backup of this machine's original file, and the scripts that
applied [[runtime]]'s corrections back into the four area files).

## Verdict vocabulary

| Verdict | Meaning |
|:---|:---|
| `covered` | Present and correctly presented. |
| `outdated` | Present, but the wording or presentation reflects an older doc state, or omits a condition the docs state. |
| `wrong` | Present, but the app's behaviour contradicts the documentation. |
| `missing` | Not present at all. |

## Sizing rubric

Sizes are about **implementation cost in this codebase**, not about how much the finding
matters. Ranking carries the impact; size carries the effort.

| Size | Means | Typical shape |
|:---|:---|:---|
| **S** | A change inside an existing editor or call site: a key, a widget type, a label, a tooltip, its i18n keys, a flag added to an existing `wsl.exe` invocation. No new file, no new screen, no new architecture. | a `settings_screen.dart` key row · a `wsl.conf` key · one `--flag` |
| **M** | A new section, dialog or service, **or** a rewrite of an existing read/write path that needs its own tests. | the `.wslconfig` engine · the `wsl.conf` writer · a WSL capability service · a disk-space panel |
| **L** | A new screen or subsystem, with its own state, files on disk and lifecycle. | custom-distro `.wsl` packaging |

The Phase 04 brief's rubric says S = "a key added to an existing editor", M = "a new
section or dialog", L = "a new screen or subsystem". Two of this audit's most severe
findings are none of those — they are rewrites of existing writers. They are sized **M**
under the extended rule above, and each says so on its own row, so nobody reads "M" as
"new dialog" and goes looking for one.

## Ranking rubric

Impact tiers, highest first. Within a tier, an item with a reported issue behind it
outranks one without.

| Tier | Criterion |
|:---|:---|
| **0** | Destroys or silently discards user data or configuration, or crashes. |
| **1** | The app displays state that is not true, or writes a value that never takes effect — the user believes something false. |
| **2** | A documented behaviour or condition exists and the app cannot express or enforce it. |
| **3** | A documented capability is absent and users have asked for it. |
| **4** | Absent capability with no reported demand; cosmetic; hygiene. |

## Evidence — findings mapped to reported issues

The area files were written from the docs and the code alone, so every severity claim in
them is judgement. This section supplies the missing half: the
`bostrot/wsl2-distro-manager` issue tracker (183 issues, open and closed, read
2026-08-28) matched against the findings.

**Direct** = the issue describes the exact mechanism a finding predicts. **Plausible** =
the symptom matches but the report carries no repro or environment. **Adjacent** = same
area, different mechanism — recorded so Phase 05 does not overclaim.

| Issue | State | What was reported | Finding | Strength |
|:---|:---|:---|:---|:---|
| [#280](https://github.com/bostrot/wsl2-distro-manager/issues/280) | closed | "Move" ran with no prompt, then the distro was gone | [[cli-flags]] CC-2 — `move()` is export → unregister → import | **direct** — the destructive middle step is exactly what `--manage --move` avoids |
| [#185](https://github.com/bostrot/wsl2-distro-manager/issues/185) | closed | hostname set from the app never reaches `/etc/wsl.conf`; a manual `echo -e >> /etc/wsl.conf` works | [[wslconf-keys]] CC-1 / CC-2 | **direct** — the user's own workaround is the writer's third branch, the only one that is not `sed` |
| [#309](https://github.com/bostrot/wsl2-distro-manager/issues/309) | **open** | setting a default user at creation replaced `wsl.conf`, losing `[boot] systemd=true` | [[wslconf-keys]] CC-1 | **direct** — the create path was since changed to `setSetting` (`create_dialog.dart:324`, commit `4913741`, 2026-06-16), but the issue is still open and the writer beneath it is still section-blind |
| [#261](https://github.com/bostrot/wsl2-distro-manager/issues/261) | closed | "the actual status of Systemd is the opposite of the setting item display" | [[wslconf-keys]] CC-3 | **direct** — a documented-`true` key rendered from `?? false` |
| [#225](https://github.com/bostrot/wsl2-distro-manager/issues/225) · [#234](https://github.com/bostrot/wsl2-distro-manager/issues/234) | closed | the app offered `pageReporting`; WSL then warned `Unknown key 'wsl2.pageReporting'` on every start | [[wslconfig-keys]] CC-8 (the orphan string is what remains of it) and CC-3 | **direct** — and the one time a user has reported reading WSL's stderr, which is where [[runtime]] R-4's silent rejections also land |
| [#87](https://github.com/bostrot/wsl2-distro-manager/issues/87) | closed | Save overrides hand-written `.wslconfig` settings | [[wslconfig-keys]] CC-3 | **direct** — the re-emit-everything-into-`[wsl2]` path |
| [#224](https://github.com/bostrot/wsl2-distro-manager/issues/224) | closed | "I have no idea what format to define the amount of swap space in" | the `swap` row (size key, no size widget) + the tooltip diff | **direct** — closed by adding the `(e.g. 8GB, 512MB)` examples; the widget was never fixed |
| [#268](https://github.com/bostrot/wsl2-distro-manager/issues/268) | **open** | typing `wsl` lands in root at `/mnt/c/Users/…` after creating a distro with this app | [[wslconf-keys]] CC-6 (`[user] default` not editable) + `--set-default` | **direct** |
| [#313](https://github.com/bostrot/wsl2-distro-manager/issues/313) | **open** | delete a distro, recreate it under the same name, it still starts as the deleted user | [[wslconf-keys]] CC-6 — the `[user] default` / `StartUser_` prefs lifecycle | **direct**, but **the mechanism is already fixed** — [[coverage-sweep]] Sweep 4: `clearDistroPrefs` (`helpers.dart:388`) runs from `WSLApi.remove` (`wsl.dart:951`). The issue is open against a version that predates it; verify before rebuilding |
| [#192](https://github.com/bostrot/wsl2-distro-manager/issues/192) | closed | default user lost after shrink/cleanup | same | **direct** |
| [#303](https://github.com/bostrot/wsl2-distro-manager/issues/303) | **open** | Compact fills the drive; no free-space pre-check | [[features]] F-11 | **direct** |
| [#133](https://github.com/bostrot/wsl2-distro-manager/issues/133) | closed | "Disk shrinking" | F-3 (reclaim half) + F-11 | **direct** |
| [#103](https://github.com/bostrot/wsl2-distro-manager/issues/103) | **open** | set the WSL version per distro and the default version | [[cli-flags]] `--set-version` / `--set-default-version` | **direct** |
| [#300](https://github.com/bostrot/wsl2-distro-manager/issues/300) | closed | "点击设置闪退" — the app exits the moment Settings is clicked (v1.10.0, no environment given) | [[wslconfig-keys]] CC-9 | **plausible** — the symptom is exactly CC-9's, but the report has no `.wslconfig` and no repro. A candidate, not proof; reproducing CC-9 would retro-explain it |
| [#203](https://github.com/bostrot/wsl2-distro-manager/issues/203) | **open** | export / import feature requests | [[cli-flags]] CC-3 (`--export --format`) | adjacent |
| [#239](https://github.com/bostrot/wsl2-distro-manager/issues/239) · [#279](https://github.com/bostrot/wsl2-distro-manager/issues/279) · [#15](https://github.com/bostrot/wsl2-distro-manager/issues/15) | **open** ×2 | add the distro to the Windows Terminal menu; launch through its dynamic profile | F-8 — `wsl-distribution.conf`'s `[windowsterminal]` and `[shortcut]` are the documented mechanism for exactly this | **direct for F-8's motivation**, though an `--import`-created distro's missing profile has other causes too |
| [#14](https://github.com/bostrot/wsl2-distro-manager/issues/14) · [#59](https://github.com/bostrot/wsl2-distro-manager/issues/59) | closed | bridged networking; per-distro IPs | F-1 `networkingMode` | adjacent — both predate `mirrored` |
| [#310](https://github.com/bostrot/wsl2-distro-manager/issues/310) | **open** | a screen reader finds unlabelled controls | [[wslconf-keys]] CC-4 (no labels, no descriptions, no i18n) | adjacent — the report is about the distro action bar, not this dialog, but CC-4 is the same defect class and the dialog would fail the same test |
| [#159](https://github.com/bostrot/wsl2-distro-manager/issues/159) | closed | "Load settings for existing distros" | `loadDistroSettings` exists because of this; V-7's spelling risk lives in it | context |

Nine of those twenty are still open. **Every tier-0 and tier-1 item below has at least one
reported issue behind it** — the audit's severity judgements survive contact with the
issue tracker, which is the open question [[verification]] and [[features]] both flagged
in their "what was not examined" sections.

## Finding registry — every finding, sized

Every finding in the seven files, with its size and the item that closes it. Nothing is left
without a destination: items are **P05-01 … P05-24**, and findings with no item appear in
*Not scheduled* below with a reason.

### [[wslconfig-keys]] — `.wslconfig`

| Finding | Verdict | Size | Item |
|:---|:---|:---:|:---|
| CC-9 slider asserts on `memory=8589934592` / `processors=64` (V-1, R-9) | wrong | S | **P05-01** |
| `memory=6144MB` silently collapses to `1GB` (R-10) | wrong | S | **P05-01** |
| CC-2 `readConfig` strips every space inside a value | wrong | M | **P05-02** |
| CC-3 section-blind read and write; a key relocated to `[wsl2]` is rejected by WSL (R-4) | wrong | M | **P05-02** |
| CC-4 case-sensitive matching against a case-insensitive format; the appended line loses (V-5, R-8) | wrong | M | **P05-02** |
| CC-5 comment lines parsed as keys; `#` only, never `;` (R-7) | wrong | M | **P05-02** |
| CC-10 path values written with single backslashes; WSL discards the line (R-6) | wrong | M | **P05-02** |
| `kernelCommandLine` mangled by CC-2 | wrong | M | **P05-02** |
| CC-11 a key can be added and changed but never removed; blocks the tri-state (S-2) | wrong | M | **P05-02** |
| CC-5 write half — unanchored regex, a commented-out key absorbs the write (S-3) | wrong | M | **P05-02** |
| CC-1 seven documented-`true` toggles render off when unset | wrong | S | **P05-04** |
| CC-7 restart requirement stated but hedged; Save never offers it (R-11) | covered | S | **P05-07** |
| `networkingMode`, `autoMemoryReclaim` rendered as free text | wrong | S | **P05-09** |
| CC-6 five documented conditional dependencies honoured nowhere | missing | S | **P05-10** |
| `swap`, `defaultVhdSize` — size keys in plain text boxes | outdated | S | **P05-11** |
| `vmIdleTimeout`, `maxCrashDumpCount` — numeric keys, no validation, no unit | outdated | S | **P05-11** |
| `kernel`, `swapFile` — path keys with no file picker | outdated | S | **P05-11** |
| `guiApplications`' tooltip invents a Windows 11 restriction (V-3) | wrong | S | **P05-12** |
| `safeMode`'s tooltip is truncated, dropping the only WSL-version floor in the table (V-4) | outdated | S | **P05-12** |
| 14 further incomplete tooltips; `processors` drops "logical"; two English defects in `globalconfigurationinfo-text` | outdated | S | **P05-12** |
| CC-8 orphaned `unusedmemoryinfo-text` (`pageReporting`) in nine locales | outdated | S | **P05-12** |
| R-1 `nestedVirtualization` is refused by the host CPU, and WSL says so on stderr | new | M | **P05-08** |
| `systemDistro`, `kernelDebugPort` (Intune-only) absent | missing | — | not scheduled |
| S-4 `Default Distro Location` / `General Data Location` share the `_settings` namespace | n/a | — | not scheduled |

### [[wslconf-keys]] — `wsl.conf`

| Finding | Verdict | Size | Item |
|:---|:---|:---:|:---|
| CC-1 section-blind `sed`; `[automount] enabled` and `[interop] enabled` overwrite each other | wrong | M | **P05-03** |
| CC-2 any value containing `/` breaks the `sed`, silently — including `automount.root`'s documented default | wrong | M | **P05-03** |
| CC-7 free-text values interpolated unescaped into a **root** shell (V-6) | wrong | M | **P05-03** |
| V-7 prefs keyed on the file's spelling, not the widget's | risk | M | **P05-03** |
| `boot.command`, `automount.root` unusable in practice | wrong | M | **P05-03** |
| CC-3 six documented-`true` toggles render off | wrong | S | **P05-04** |
| CC-6 `[user] default` written at creation, never editable — and shadowed by the dialog's **Start user** box (S-1) | missing | S | **P05-05** |
| CC-5 every keystroke writes; no restart signal; `--terminate` suffices (R-12) | missing | S | **P05-06** |
| CC-4 no labels, no descriptions, no `.i18n()` anywhere in the dialog | missing | S | **P05-13** |
| `automount.options` — a 7-token composite in a raw text box; the `metadata` precondition unstated | outdated | S | **P05-13** |
| `[boot] protectBinfmt`, `[gpu] enabled`, `[time] useWindowsTimezone` absent | missing | S | **P05-14** |

### [[cli-flags]] — `wsl.exe`

| Finding | Verdict | Size | Item |
|:---|:---|:---:|:---|
| CC-1 `--version` / `--status` never invoked; no version gating possible | missing | M | **P05-08** |
| CC-2 `--manage --move` | missing | M | **P05-15** |
| CC-2 `--manage --resize`, `--manage --set-sparse`, and `--system` | missing | M | **P05-16** |
| CC-2 `--manage --set-default-user` | missing | S | **P05-05** |
| CC-3 every export is an uncompressed tar; `--format` unused | missing | S | **P05-17** |
| `--import-in-place` — `copyVhd()` copies the VHD twice | missing | S | **P05-18** |
| `--set-default`, `--set-version`, `--set-default-version` | missing | S | **P05-19** |
| `--list --verbose` — state and version in one call | missing | S | **P05-20** |
| CC-5 dead `install()` carrying the `-d` ≠ `--name` trap | wrong | S | **P05-21** |
| CC-4 two hand-built `--mount` argument strings, one through an elevation path | risk | S | **P05-21** |
| `--update`, `--update --web-download` | missing | M | **P05-23** |
| `--shell-type`, `--distribution-id`, `--shutdown --force`, `--uninstall`, `--debug-shell`, `--list --online`, `--list --all`, `--import --version` | missing / n/a | — | not scheduled |

### [[features]] — capability surfaces

| Finding | Verdict | Size | Item |
|:---|:---|:---:|:---|
| F-1 mirrored networking — key present, unexplained, ungated | outdated | S | **P05-09** + **P05-10** |
| F-2 DNS tunnelling — dependants ungated, tooltips thin | outdated | S | **P05-10** + **P05-12** |
| F-3 sparse VHD — only the "newly created" half exists | missing | M | **P05-16** |
| F-4 `wsl --manage` | missing | M | **P05-15**, **P05-16**, **P05-05** |
| F-5 "WSL Settings" — Microsoft ships one; this app already uses the name for something else (V-8) | missing | S | **P05-22** + research item **R-A** |
| F-6 systemd — no distro-default awareness, no restart prompt, broken writer | outdated | M | **P05-03** + **P05-04** + **P05-06** |
| F-7 WSL plugins | missing | L | not scheduled |
| F-8 custom-distro distribution (`.wsl`, `wsl-distribution.conf`) | missing | L | **P05-24** |
| F-9 WSL version awareness | missing | M | **P05-08** |
| F-10 the 8-second rule, surfaced for one file of two | outdated | S | **P05-06** + **P05-07** |
| F-11 disk-space management | missing | M | **P05-16** |

[[verification]] V-1…V-8 and [[runtime]] R-1…R-13 are corrections and evidence attached to
the findings above, not separate work: each appears in these tables through the finding it
changed. V-2 — the `ComboBox` pattern already exists three times in this codebase — is the
reason P05-09 is **S** rather than **M**.

## Ordered implementation list for Phase 05

**This list is the input to Phase 05.** It is linear and complete: work it top to bottom.
Sizes total **17 S · 6 M · 1 L**.

Order is impact-first, subject to dependencies. Two placements look like ranking errors
and are not:

- **P05-02 and P05-03 come before almost every key-level item.** Adding a key or a combo
  box to an editor whose writer corrupts what it writes only ships a nicer way to lose
  data.
- **P05-08, the enabling item, sits at position 8, not first.** Nothing in tiers 0–1 needs
  a version check; everything from P05-15 on does.

| # | Item | Size | Tier | Closes | Evidence |
|---:|:---|:---:|:---:|:---|:---|
| 1 | Clamp and unit-parse the size / number sliders | S | 0 | `.wslconfig` CC-9, R-9, R-10 | #300 (plausible), #224 |
| 2 | Replace the `.wslconfig` read/write engine | M | 0 | `.wslconfig` CC-2, CC-3, CC-4, CC-5, CC-10, **CC-11**, V-5, R-4, R-6, R-7, R-8, S-2, S-3 | #87, #225, #234 |
| 3 | Replace the `wsl.conf` writer | M | 0 | `wsl.conf` CC-1, CC-2, CC-7, V-7 | #185, #309, #261 |
| 4 | Tri-state booleans: show the documented default | S | 1 | `.wslconfig` CC-1, `wsl.conf` CC-3 | #261 |
| 5 | `[user] default` editor and the default-user lifecycle | S | 1 | `wsl.conf` CC-6, `--manage --set-default-user` | #268, #313, #192 |
| 6 | `wsl.conf` dialog: restart scope, and stop writing per keystroke | S | 1 | `wsl.conf` CC-5, F-10 (per-distro half), R-12 | #185, #261 |
| 7 | Global Settings: offer the restart on Save, and stop hedging | S | 1 | `.wslconfig` CC-7, F-10 (global half), R-11 | — |
| 8 | WSL capability service: `--version`, `--status`, and WSL's stderr | M | 2 | `cli` CC-1, F-9, R-1, R-2 | — |
| 9 | `SettingsType.enumeration` for the two enum keys | S | 2 | `networkingMode`, `autoMemoryReclaim`, V-2, F-1 (half) | #14 |
| 10 | Honour the five documented conditional dependencies | S | 2 | `.wslconfig` CC-6, F-1, F-2 | — |
| 11 | Right widget for each documented value type | S | 2 | `swap`, `defaultVhdSize`, `vmIdleTimeout`, `maxCrashDumpCount`, `kernel`, `swapFile` | #224 |
| 12 | `.wslconfig` tooltip pass — 17 rewrites, 2 English defects, 1 orphan deleted | S | 2 | V-3, V-4, CC-8, the Part 3 tooltip diff | #224, #225, #234 |
| 13 | Labels, descriptions and i18n for the `wsl.conf` dialog | S | 2 | `wsl.conf` CC-4, `automount.options` guidance | #310 (adjacent) |
| 14 | The four missing `wsl.conf` keys | S | 2 | `protectBinfmt`, `gpu.enabled`, `time.useWindowsTimezone` | — |
| 15 | `wsl --manage --move` replaces the export / unregister / import move | M | 0 † | `cli` CC-2 (move), F-4 (half) | #280, #166 |
| 16 | Disk-space surface: usage, `--resize`, `--set-sparse` | M | 3 | F-3 (reclaim half), F-11, `--system` | #303, #133 |
| 17 | Compressed exports (`--export --format`) | S | 3 | `cli` CC-3 | #203 |
| 18 | `--import-in-place` for the VHD copy path | S | 3 | `cli` `--import-in-place` | — |
| 19 | `--set-default`, `--set-version`, `--set-default-version` | S | 3 | the three version / default verbs | #103, #268 |
| 20 | One `--list --verbose` instead of two list calls | S | 4 | `cli` `--list --verbose` | — |
| 21 | Hygiene: delete `install()`, fix the two hand-built `--mount` argument paths | S | 4 | `cli` CC-4, CC-5 | — |
| 22 | Resolve the "WSL Settings" name collision | S | 3 | F-5 (actionable half), V-8 | — |
| 23 | `wsl --update` / `--update --web-download` from the app | M | 3 | `cli` `--update` | — |
| 24 | Custom-distro distribution: `.wsl`, `wsl-distribution.conf` | L | 3 | F-8 | #239, #279, #15 |

† **P05-15 is tier 0 by impact** — it is the only finding in this audit with a user report
of actual data loss (#280) — but it depends on P05-08, so it is scheduled after it. If
Phase 05 runs out of budget before position 15, promote it: an interim **S**-sized guard
(a confirmation dialog naming the export path, which is what #280 itself asked for) is
worth more than items 9–14 combined and needs nothing from P05-08.

### Item detail

**P05-01 — Clamp and unit-parse the size / number sliders · S · tier 0**
`settings_screen.dart:1194-1240`. Extract a size parser — bare `8589934592` is bytes,
`6144MB` and `8GB` carry units, a bare small number keeps the app's current GB convention
— and clamp into `[sizeMin, sizeMax]` before the `Slider` constructor sees the value. An
out-of-range value must render as an editable number with a warning, never as a clamped
lie.
*Done when:* a debug build opens Settings against `.wslconfig` files containing
`memory=8589934592`, `memory=6144MB` and `processors=64` without throwing, and Save
round-trips each unchanged; unit tests cover the parser.
*Do the reproduction before the fix.* It is the one step [[verification]] and [[runtime]]
both left undone — a one-line file edit and an app launch — and it decides whether #300
was this bug.

**P05-02 — Replace the `.wslconfig` read/write engine · M · tier 0**
`wsl.dart:534-646`, `settings_screen.dart:78-81, 271-317`. A sectioned, case-insensitive
model — the shape `getWSLConf` (`wsl.dart:1824`) already has for `wsl.conf` — preserving
comments, blank lines, and unknown keys **in their own sections**; values escaped on write
and unescaped on read (`\` → `\\`); no space stripping; `#` comments only, never `;`
(R-7). `saveSettings` must write each key back to the section it came from instead of
consulting a hardcoded seven-key list.
*Done when:* a `.wslconfig` carrying lowercase keys, comments, a hand-added
`[experimental]` key and a spaced `kernelCommandLine` survives load → Save byte-identical
apart from the key the user edited, and `wsl --shutdown && wsl -d <distro> true` prints no
diagnostic — [[runtime]]'s oracle, which makes this an exact and cheap regression test.

**P05-03 — Replace the `wsl.conf` writer · M · tier 0**
`assets/scripts/settings.bash`, `wsl.dart:1807-1846`, `settings_dialog.dart:399-433`. Read
with `getWSLConf`, mutate the model, write the whole file back in one in-distro command
through `wslShellArgs` with the payload escaped (or base64-encoded) — no `sed`, no per-key
string templating, which is what makes CC-1, CC-2 and CC-7 one fix rather than three.
`setSetting` must return the real exit status, and a failure must reach the user instead of
being swallowed by `showOutput: false`. Normalise section and key spelling on read so prefs
and widgets agree (V-7).
*Done when:* toggling `[interop] enabled` leaves `[automount] enabled` untouched;
`automount.root=/mnt/`, a `boot.command` containing slashes, and a `network.hostname`
containing a `"` all persist verbatim; a write to a read-only `/etc/wsl.conf` reports
failure rather than returning `true`; #185's and #309's repro steps pass.

**P05-04 — Tri-state booleans · S · tier 1 · hard-depends on P05-02**
`settings_screen.dart:1206-1215` and `settings_dialog.dart:346-370`. Unset must render as
the documented default with an "unset — default: on" affordance, not as off. Thirteen keys
across the two editors.
*This is not independently shippable.* [[coverage-sweep]] CC-11 established that the app
has **no way to remove a key from `.wslconfig`** — `saveSettings` skips empty values and
`setConfig` has no delete branch — so the third state has nowhere to be written until
P05-02 lands. Do not start P05-04 first.
*Done when:* a distro with no `wsl.conf` shows `automount.enabled` as on, Save does not
write keys the user never touched, and returning a key to *unset* physically removes its
line from `.wslconfig`.

**P05-05 — `[user] default` editor · S · tier 1**
Add a `[user]` section to `wslSettings` (`settings_dialog.dart:288-343`); the value already
reaches prefs through `loadDistroSettings` (`:413`) and is then dropped. Where WSL ≥ 2.5 is
present (P05-08), prefer `--manage --set-default-user` and fall back to writing the key —
`<distro> config --default-user` remains documented as broken for imported distros.
**Place it next to the existing *Start user* box and label both.** [[coverage-sweep]] S-1:
that box is tooltipped `wsldefaultuser-text` and only sets `--user` on terminals this app
launches, so it is what a user hunting for this setting finds instead — shipping a second
user field without distinguishing them makes the dialog worse, not better.
**Scope reduced.** The lifecycle half this item carried — "clear `StartUser_` / `StartPath_`
on deletion (#313)" — is **already implemented**: `clearDistroPrefs` (`helpers.dart:388`)
is called from `WSLApi.remove` (`wsl.dart:951`) and wipes all eleven per-distro prefixes on
unregister, and `loadDistroSettings` clears its twelve `wsl.conf` `knownKeys` on every
dialog open. Verify against #313 rather than reimplementing.
*Done when:* changing the default user in the dialog survives a `--terminate` and applies
to `wsl` typed in an external terminal, not just to launches from the app.

**P05-06 — `wsl.conf` dialog: restart scope, and stop writing per keystroke · S · tier 1**
Debounce or commit-on-blur instead of one in-distro script execution per character
(`settings_dialog.dart:358`, `:390`), and state the per-distro rule with a **Terminate
distro** button — `wsl --terminate <distro>` is sufficient here ([[runtime]] R-12); no
global shutdown is needed, which makes this cheaper than P05-07.
*Done when:* typing a 12-character hostname runs the writer once, and the dialog offers the
terminate that makes the change live.

**P05-07 — Global Settings: offer the restart on Save · S · tier 1**
`settings_screen.dart:1017`, `en.json:117`. Rewrite `globalconfigurationinfo-text` to say
changes take effect **after WSL restarts** — not "you may need to", which [[runtime]] R-11
measured as unconditional on this build — and fix "and ,later" and "take affect". Prompt
"Restart WSL now?" after Save, wired to the existing `WSLApi().restart()`.
*Done when:* the corrected string is present in all nine locales and Save offers the
restart.

**P05-08 — WSL capability service · M · tier 2**
One service that runs `wsl --version` and `wsl --status` once, caches the result, and
exposes `isStoreWsl`, `version` and `atLeast(2, 5)`. Read WSL's **stderr** as well as its
exit code: [[runtime]] R-1 shows `nestedVirtualization` is refused by the host CPU with a
warning no version check can predict, and the unknown-key diagnostics behind R-4 arrive on
the same channel. Surface WSL's own warnings instead of inventing gates.
*Done when:* the app shows its WSL version somewhere the user can find it, gates the
`--manage` items on it, and displays WSL's warning text when a key is refused.
*Scope note:* every **H** flag exists in 2.6.3 ([[runtime]] R-2), so one coarse "is this
2.x / ≥ 2.5" check is enough — do not build per-flag probing.

**P05-09 — `SettingsType.enumeration` · S · tier 2**
Add the member at `settings_screen.dart:20` and render a `ComboBox`; the pattern already
exists at `create_dialog.dart:522`, `mount_dialog.dart:334` and `:515` (V-2). Values:
`networkingMode` = `none | nat | bridged | mirrored | virtioproxy`, with `bridged` marked
deprecated since WSL 2.4.5; `autoMemoryReclaim` = `disabled | gradual | dropCache`.
*Done when:* neither key can be given an unrecognised value from the UI.

**P05-10 — Honour the five documented conditional dependencies · S · tier 2**
`dnsTunneling` → {`bestEffortDnsParsing`, `dnsTunnelingIpAddress`}; `autoProxy` →
`initialAutoProxyTimeout`; `networkingMode=mirrored` → {`ignoredPorts`,
`hostAddressLoopback`} **and** `localhostForwarding` becomes ignored; `networkingMode=NAT`
→ `dnsProxy`. Disable with a stated reason; do not hide.
*Done when:* selecting `mirrored` greys `localhostForwarding` with the documented reason
and enables its two dependants.

**P05-11 — Right widget for each documented value type · S · tier 2**
`swap` and `defaultVhdSize` get P05-01's size treatment; `vmIdleTimeout` and
`maxCrashDumpCount` get numeric input with the unit in the label (ms, count) and their
documented defaults as placeholders; `kernel` and `swapFile` get file pickers writing
through P05-02's escaping, so they do not reproduce CC-10 the way `kernelModules`' picker
does today.
*Done when:* no documented `size`, `number` or `path` key is an unvalidated free-text box.

**P05-12 — `.wslconfig` tooltip pass · S · tier 2**
Rewrite the 16 `outdated` and 1 `wrong` strings against [[verification]] Part 3: restore
every "Only applicable when…" clause and every default, restore `safeMode`'s WSL 0.66.2+
floor, delete `guiApplications`' invented Windows 11 restriction, restore "logical" to
`processors`, fix "Only available ,for Windows 11" and "take affect", and delete
`unusedmemoryinfo-text` from all nine locales (CC-8 — the residue of the key #225 and #234
reported).
*Done when:* the diff in [[verification]] Part 3 reads 27 covered.

**P05-13 — Labels, descriptions and i18n for the `wsl.conf` dialog · S · tier 2**
`settings_dialog.dart:346-397` renders `setting.uppercaseFirst()` and no description at
all. Give each of the eleven keys a localised label and description, including
`automount.options`' token list and the documented fact that `umask` / `fmask` / `dmask`
are inert without `metadata`.
*Done when:* no label in the dialog is derived from a Dart identifier.

**P05-14 — The four missing `wsl.conf` keys · S · tier 2**
`[gpu] enabled`, `[time] useWindowsTimezone`, `[boot] protectBinfmt` — `[user] default` is
P05-05. Write `protectBinfmt`'s description from behaviour, **not** from the upstream
sentence: the documented one is inverted (it describes the `false` case), as recorded in
[[wslconf-keys]].
*Done when:* all fifteen documented keys are editable.

**P05-15 — `wsl --manage --move` · M · tier 0, scheduled after P05-08**
Replace `WSLApi.move` (`wsl.dart:1649-1790`) with the native verb where available, keeping
the export → unregister → import path only as a fallback for older WSL, behind the same
size floor and prefs recovery marker it uses now. Either way, confirm destructively-shaped
operations before starting — #280 asked for precisely that.
*Done when:* a move on WSL ≥ 2.5 issues one `--manage --move` and never unregisters the
distro.

**P05-16 — Disk-space surface · M · tier 3**
Usage from `wsl --system df -h /mnt/wslg/distro` alongside the `ext4.vhdx` size the app
already reads for `move()`'s safety floor (`wsl.dart:1743-1757`); `--manage --resize`
(integers only — `2.5TB` is rejected); `--manage --set-sparse` for existing distros,
presented so it cannot be confused with `[experimental] sparseVhd`, which only affects new
ones. Add the free-space pre-check #303 asks for to the existing Compact action.
*Done when:* a user can see a distro's real usage, reclaim it, and cannot start a compact
that will not fit.

**P05-17 — Compressed exports · S · tier 3**
`--export --format tar.gz | tar.xz | vhd` (`wsl.dart:903-916`), with the format chosen in
the export UI, and `move()`'s intermediate no longer an uncompressed tar named `.ext4`.

**P05-18 — `--import-in-place` · S · tier 3**
`copyVhd()` (`wsl.dart:840-900`) file-copies `ext4.vhdx` and then `--import --vhd` copies
it a second time. Import the already-copied file in place.

**P05-19 — Default distro and WSL version verbs · S · tier 3**
`--set-default` (#268), `--set-version` per distro and `--set-default-version` (#103).
Gate on P05-08.

**P05-20 — One `--list --verbose` · S · tier 4**
Replaces the `--list --quiet` + `--list --running --quiet` pair (`wsl.dart:1294`, `:1564`)
and yields each distro's WSL version for free.

**P05-21 — Hygiene · S · tier 4**
Delete `WSLApi.install` (`wsl.dart:970-973`) — dead, and carrying the `-d` ≠ `--name` trap
`AGENTS.md` documents. Convert `mount_service.dart:248-292`'s string-built `--mount`
command to the `List<String>` form its own remote branch already uses, and drop the
pre-quoted path at `:313`.

**P05-22 — Resolve the "WSL Settings" name collision · S · tier 3**
`wslsettings-text` (`en.json:134`) names this app's **`wsl.conf`** dialog, while Windows
now ships a Start-menu app of that exact name editing **`.wslconfig`** (V-8). Rename this
app's dialog (e.g. "Distro Settings") across all nine locales, and reference Microsoft's
app by name on the screen that edits the same file it does.

**P05-23 — `wsl --update` from the app · M · tier 3**
Plus `--update --web-download` for machines where the Store is blocked
(`compare-versions.md:102`). Gate on P05-08, which is where the current version comes from.

**P05-24 — Custom-distro distribution · L · tier 3**
`.wsl` packaging, `wsl --install --from-file`, and `/etc/wsl-distribution.conf` —
`[oobe]`, `[shortcut]`, `[windowsterminal]`. The natural extension of the existing template
feature (`lib/api/templates.dart`, `lib/screens/template_screen.dart`), the documented
answer to #239 and #279, and the fix for the missing-launcher root cause behind #268.

### Research item, not implementation

**R-A — Benchmark against Microsoft's WSL Settings app.** [[features]] F-5's two open
questions cannot be answered from `microsoftdocs/wsl@8842def`, because the page does not
exist: which keys the first-party GUI exposes and with what widgets, and whether concurrent
editing of `%UserProfile%\.wslconfig` by both apps conflicts. Needs the shipping app or
`microsoft/WSL`. Worth doing **before** P05-11, as the natural benchmark for the widget-type
decisions — but not a blocker, since P05-11 already has the docs' value types.

## Not scheduled, with reasons

| Finding | Why not |
|:---|:---|
| `systemDistro`, `kernelDebugPort` | `intune.md`-only, no reference-table row; enterprise and kernel-debug plumbing, not settings-screen keys |
| S-4 `Default Distro Location` / `General Data Location` sharing the `_settings` map with `.wslconfig` keys | app preferences, not WSL config keys, and the name-match exclusion (`settings_screen.dart:309-310`) is correct today. Recorded in [[wslconfig-keys]] with verdict `n/a` so the coverage claim is complete; nothing to implement |
| F-7 WSL plugins | a developer-extension surface; no demand in 183 issues |
| `--shutdown --force` | documented as data-losing; the app already has a safe `--shutdown` |
| `--uninstall` | removes WSL itself; keeping it out of a distro manager's UI is deliberate |
| `--debug-shell` | requested once, in 2022 (#10, closed); diagnostic surface for plugin authors |
| `--list --online`, `--list --all` | the app ships its own catalogue (`images.json`, `distroRootfsLinks`) |
| `--import --version` | imports inherit the machine default; P05-19 gives the user that control directly |
| `--shell-type`, `--distribution-id` | `--exec` already solves the first; the app keys everything by name |
| `automount.options` decomposed editor | deferred, not rejected — P05-13 supplies the description and the `metadata` precondition, which is what the #224-class confusion needs. A per-token editor is an **M** with no reported demand |
| Intune policy detection | `*UserSettingConfigurable` can lock any `.wslconfig` key to its default (`intune.md:41-43`), which would make the app's writes silently ineffective. Real, unreachable from the docs clone, and no detection mechanism was found. Recorded so it is not rediscovered as a bug |
| WSL 1 behaviour (`case=force`, `--set-version 1`) | the app targets WSL 2; P05-19 exposes `--set-version` without adopting WSL 1 semantics anywhere else |

## New i18n keys the S-sized items need

Input to this phase's final task. Names follow the existing convention (lowercase, no
separators, `-text` suffix) and were checked against the 284 keys already in `en.json`:
`wsldefaultuser-text`, `stopwsl-text`, `selectfile-text`, `move-text` and `size-text`
already exist and should be reused rather than duplicated.

| Item | Keys |
|:---|:---|
| P05-04 | `settingdefault-text` ("Default"), `settingunset-text` ("Not set — using the default") |
| P05-05 | `defaultuserinfo-text`; reuse `wsldefaultuser-text` |
| P05-06 | `wslconfrestart-text` ("Restart this distro to apply"), `terminatedistro-text` |
| P05-07 | `restartwslnow-text`, `restartwslprompt-text`; **rewrite** `globalconfigurationinfo-text` |
| P05-09 | `deprecatedvalue-text` ("deprecated since WSL 2.4.5") |
| P05-10 | `onlyapplieswhen-text`, `ignoredinmirrored-text` |
| P05-11 | `milliseconds-text`, `unitexample-text` |
| P05-12 | **rewrites only** — 17 existing `*info-text` values; **delete** `unusedmemoryinfo-text` |
| P05-13 | 11 label + 11 description pairs for the `wsl.conf` keys (`bootsystemd-text` / `bootsystemdinfo-text`, `automountenabled-text` / `automountenabledinfo-text`, …) |
| P05-14 | `gpu-text`, `time-text`, `user-text` section headers; `gpuenabled-text`, `usewindowstimezone-text`, `protectbinfmt-text` and their `…info-text` pairs |
| P05-19 | `setdefaultdistro-text`, `setwslversion-text` |
| P05-22 | **rename** `wslsettings-text`; add `microsoftwslsettings-text` |

Roughly **45 new keys and 18 rewrites**, across nine locales. The three strings
[[verification]] corrected — `guiinfo-text`, `safemodeinfo-text`, `processorinfo-text` —
must be re-checked in **all** locales, not just `en.json`: only English was ever diffed.

## Status

| Phase 04 task | State |
|:---|:---|
| Source material fetched and pinned | done — `Working/wsl-docs-source.md` |
| Documented-side inventories extracted | done — three files in `Working/` |
| Per-area findings written | done — the four area files |
| Claimed gaps re-verified against code (widget types, tooltips) | done — [[verification]] |
| Runtime behaviour verified against local WSL | done — [[runtime]] |
| **Findings sized (S/M/L), ranked, ordered for Phase 05** | **done — this file, *Ordered implementation list*** |
| False-negative sanity check | done — [[coverage-sweep]] |
| i18n keys added for the S-sized findings | pending |

**The ordered implementation list above is the Phase 05 input.** It covers every finding
in the seven files: 24 items (17 S · 6 M · 1 L), one research item, and twelve findings
explicitly not scheduled with a reason each.

The sanity check has since run ([[coverage-sweep]]) and **the item count did not change** —
its four additions folded into P05-02 and P05-05, its one withdrawal shrank P05-05, and it
added one hard dependency (**P05-04 cannot ship before P05-02**). What it did change is how
much weight the list can carry: "every key and every flag has a verdict" is now enumerated
rather than asserted.

One limit remains, stated here so the list is not read as more settled than it is: the
issue mapping is a match against reported symptoms, not a confirmed root-cause diagnosis
for each issue — #300 is marked *plausible*, not proven, and #313's mapping now needs
re-testing rather than implementing.

## Coverage limits

Each area file ends with its own "what was not examined" section; read it before quoting
a finding. [[coverage-sweep]]'s own section is the one to read before calling the audit
complete: it swept the two editors and `wsl.dart` end to end, but **not** `create_dialog.dart`,
`list_item.dart`, `docker_images.dart` or `copy_dialog.dart` (grepped for specific keys
only), and it re-checked the *app* side against the existing inventories without re-reading
the docs clone — so a documented key the first pass missed would still be invisible.

Two further limits apply to all four area files:

- **The four area files and [[verification]] were written without executing anything.**
  Every app-side claim in them is read from source at the cited line. [[runtime]] is the
  exception and supersedes them where they conflict: it executed WSL 2.6.3.0, wrote config
  keys and observed them taking effect. The app itself has still never been launched for
  this audit — see [[runtime]]'s *What was not examined*.
- **The docs are the yardstick, not the WSL implementation.** The inventories are
  exhaustive against `microsoftdocs/wsl@8842def` plus one local `wsl.exe --help` run. WSL
  has no "dump all config keys" verb, so a key that exists in the binary and in neither
  source is invisible to this audit — though [[runtime]]'s unknown-key probe can *test* any
  candidate name cheaply, which is how the two Intune-only keys were confirmed real.
