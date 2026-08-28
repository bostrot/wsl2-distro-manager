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

- **[[wslconfig-keys]]** — per-key table for `[wsl2]` and `[experimental]`, plus eight
  cross-cutting findings about the editor and the `.wslconfig` parser/writer.
- **[[wslconf-keys]]** — per-key table for all seven `wsl.conf` sections, plus six
  cross-cutting findings, two of them data-affecting.
- **[[cli-flags]]** — every documented (**D**) and `--help`-only (**H**) `wsl.exe` command
  against every invocation in `lib/`.
- **[[features]]** — eleven whole capabilities, including the ones that are "covered" at
  key level and still unusable.
- **[[verification]]** — the second pass. Read this before quoting any verdict from the four
  files above; it is where three of them changed, and it carries the full tooltip diff
  (10 covered / 16 outdated / 1 wrong) that the per-key tables only summarise.

Supporting material, outside the repo tree, under
`.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/`:
`wsl-docs-source.md` (provenance, page inventory, `ms.date` stamps),
`wslconfig-keys.md`, `wslconf-keys.md`, `wsl-exe-flags.md` (the documented-side
inventories these four files diff against).

## Verdict vocabulary

| Verdict | Meaning |
|:---|:---|
| `covered` | Present and correctly presented. |
| `outdated` | Present, but the wording or presentation reflects an older doc state, or omits a condition the docs state. |
| `wrong` | Present, but the app's behaviour contradicts the documentation. |
| `missing` | Not present at all. |

## Status

| Phase 04 task | State |
|:---|:---|
| Source material fetched and pinned | done — `Working/wsl-docs-source.md` |
| Documented-side inventories extracted | done — three files in `Working/` |
| **Per-area findings written (this set)** | **done** |
| **Claimed gaps re-verified against code (widget types, tooltips)** | **done — [[verification]]** |
| Runtime behaviour verified against local WSL | pending |
| Findings sized (S/M/L), ranked, ordered for Phase 05 | pending |
| False-negative sanity check | pending |
| i18n keys added for the S-sized findings | pending |

The ordered implementation list that feeds Phase 05 is produced by the classification
task and does **not** exist yet. Nothing in this set of files should be read as a
prioritised backlog.

## Coverage limits

Each area file ends with its own "what was not examined" section; read it before quoting
a finding. Two limits apply to all four:

- **No claim here was verified at runtime.** No WSL command was executed for this diff, no
  config key was written and observed taking effect, and no screen was exercised. Every
  app-side claim is read from source at the cited line.
- **The docs are the yardstick, not the WSL implementation.** The inventories are
  exhaustive against `microsoftdocs/wsl@8842def` plus one local `wsl.exe --help` run. WSL
  has no "dump all config keys" verb, so a key that exists in the binary and in neither
  source is invisible to this audit.
