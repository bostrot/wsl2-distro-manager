---
type: analysis
title: '.wslconfig Coverage — documented keys vs. the app'
created: 2026-08-28
tags:
  - wsl
  - docs-audit
  - wslconfig
related:
  - '[[index]]'
  - '[[wslconf-keys]]'
  - '[[cli-flags]]'
  - '[[features]]'
---

# `.wslconfig` — documented vs. app

Diff of the documented global-config surface against what
`lib/screens/settings_screen.dart` renders and what `lib/api/wsl.dart` reads and writes.

- **Documented side:** `microsoftdocs/wsl@8842def (2026-07-30)`, inventoried in
  `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/wslconfig-keys.md`.
- **App side:** `lib/screens/settings_screen.dart:1010-1156` (the two Expanders),
  `lib/api/wsl.dart:544-646` (`setConfig` / `readConfig` / `editConfig` / `writeConfig`),
  `lib/components/helpers.dart:451` (`getWslConfigPath`).
- **Verdicts:** `covered` = key present and correctly presented · `outdated` = present
  but the wording or presentation reflects an older doc state · `wrong` = present but
  the app's behaviour contradicts the docs · `missing` = not present at all.

## Headline

**Key coverage is complete. Presentation and the read/write engine are not.**

All **27** keys in the `wsl-config.md` reference tables — 20 `[wsl2]` + 7
`[experimental]` — are rendered by the app. Verified by grepping both the camelCase and
the all-lowercase spelling for every key (`.wslconfig` matching is case-insensitive and
the docs' own example file uses lowercase); every one resolves to exactly one
`settingsWidget(...)` call site in `settings_screen.dart`. There is **no missing-key
finding in this area at all**.

What the diff does produce is:

- **9 keys with an untyped or mis-typed widget** — 2 enums as free text (`networkingMode`,
  `autoMemoryReclaim`), 2 size keys and 2 numeric keys with plain text boxes (`swap`,
  `defaultVhdSize`, `vmIdleTimeout`, `maxCrashDumpCount`), 2 path keys with no file picker
  (`kernel`, `swapFile`), and a `memory` slider that silently snaps to its minimum when the
  existing value is expressed in `MB`.
- **5 documented conditional dependencies** that no part of the UI honours (CC-6).
- **7 boolean toggles** that display the opposite of the documented default when the key is
  absent from the file (CC-1).
- **4 defects in the `.wslconfig` parser/writer** that can corrupt a hand-edited file
  (CC-2 … CC-5).

## Per-key table — `[wsl2]`

| Key | Documented | App state | Verdict |
|:---|:---|:---|:---|
| `kernel` | path, escaped backslashes required (`wsl-config.md:248`) | `settings_screen.dart:1022` — plain `TextBox`, tooltip `absolutewindowspath-text` | **outdated** — no file picker (`kernelModules` has one), no escaping help |
| `kernelModules` | path to modules VHD | `:1026` — `TextBox` + `.vhdx` `FilePicker` | **wrong** — picker writes a raw single-backslash path; docs require `C:\\…` |
| `memory` | size, default 50% of host RAM | `:1042` — `Slider`, min 1, max host GB + 1, postfix `GB` | **wrong** — an existing `memory=8192MB` value fails `double.tryParse` after `replaceAll('GB','')` and silently snaps the slider to **1** |
| `processors` | number, default = host logical CPUs | `:1051` — `Slider`, min 1, max `SysInfo.cores.length` | **covered** |
| `localhostForwarding` | boolean, default `true`; **ignored when `networkingMode=mirrored`** (`wsl-config.md:305`) | `:1058` — `ToggleSwitch` | **outdated** — default-`true` shown as off when unset; the mirrored-mode override is not surfaced |
| `kernelCommandLine` | string, space-separated kernel args | `:1062` — `TextBox` | **wrong** — `readConfig` strips **all** spaces from values (`wsl.dart:623`), so `console=ttyS0 nokaslr` reloads as `console=ttyS0nokaslr` and is written back corrupted |
| `safeMode` | boolean, Win 11 + WSL 0.66.2+ | `:1066` — `ToggleSwitch` | **covered** (version floor unsurfaced — see [[features]]) |
| `swap` | **size**, default 25% of RAM, `0` disables | `:1070` — plain `TextBox` | **outdated** — a size key with no size widget and no unit hint; tooltip does carry the `8GB`/`512MB` examples |
| `swapFile` | path, default `%Temp%\swap.vhdx` | `:1072` — plain `TextBox` | **outdated** — path key with no file picker |
| `guiApplications` | boolean, default `true`, **no Win 11 restriction in the table** | `:1074` — `ToggleSwitch`, tooltip says "Only available for Windows 11" | **outdated** — the Win 11 claim is not what `wsl-config.md:225-246` annotates; the ¹ footnote is on `debugConsole`/`nestedVirtualization`/`vmIdleTimeout`, not on this key |
| `debugConsole` | boolean, default `false`, Win 11 ¹ | `:1078` — `ToggleSwitch` | **covered** (tooltip `consoleinfo-text` has a stray comma: "Only available ,for Windows 11") |
| `maxCrashDumpCount` | number, default `10` | `:1090` — `TextBox` | **outdated** — numeric key with no numeric input or validation |
| `nestedVirtualization` | boolean, default `true`, Win 11 ¹ | `:1082` — `ToggleSwitch` | **outdated** — default-`true` shown as off when unset |
| `vmIdleTimeout` | number (ms), default `60000`, Win 11 ¹ | `:1086` — `TextBox` | **outdated** — numeric key, no validation, no unit in the label |
| `dnsProxy` | boolean, default `true`, **only applies when `networkingMode = NAT`** | `:1094` — `ToggleSwitch`, tooltip `dnsproxyinfo-text` | **outdated** — the NAT-only condition is documented and absent from the tooltip |
| `networkingMode` | **enum** `none\|nat\|bridged\|mirrored\|virtioproxy`; `bridged` deprecated since WSL 2.4.5 | `:1098` — free-text `TextBox`, placeholder `nat`, tooltip lists all five values | **wrong** — an enum rendered as free text; any typo silently degrades to NAT, and the deprecation of `bridged` is not shown |
| `firewall` | boolean, default `true` (on by default from WSL 2.0.9+) | `:1102` — `ToggleSwitch` | **outdated** — default-`true` shown as off when unset |
| `dnsTunneling` | boolean, default `true`; gates `bestEffortDnsParsing` + `dnsTunnelingIpAddress` | `:1106` — `ToggleSwitch` | **outdated** — default-`true` shown as off; dependants not gated |
| `autoProxy` | boolean, default `true`, Win 11 ¹; gates `initialAutoProxyTimeout` | `:1110` — `ToggleSwitch` | **outdated** — same two problems |
| `defaultVhdSize` | **size**, default 1 TB | `:1114` — plain `TextBox` | **outdated** — size key with no size widget |

## Per-key table — `[experimental]`

| Key | Documented | App state | Verdict |
|:---|:---|:---|:---|
| `autoMemoryReclaim` | **enum** `disabled\|gradual\|dropCache`, default `dropCache` | `settings_screen.dart:1126` — free-text `TextBox`, tooltip lists the three values | **wrong** — enum as free text; an unknown value silently means `dropCache` |
| `sparseVhd` | bool, default `false` | `:1130` — `ToggleSwitch` | **covered** |
| `bestEffortDnsParsing` | bool, default `false`, **requires `dnsTunneling=true`** | `:1134` — `ToggleSwitch` | **outdated** — dependency not gated or stated |
| `dnsTunnelingIpAddress` | IPv4 string, default `10.255.255.254`, **requires `dnsTunneling=true`** | `:1138` — `TextBox`, no placeholder | **outdated** — no default shown, no IPv4 validation, dependency not gated |
| `initialAutoProxyTimeout` | ms string, default `1000`, **requires `autoProxy=true`** | `:1142` — `TextBox` | **outdated** — same three problems |
| `ignoredPorts` | CSV string, **requires `networkingMode=mirrored`** | `:1146` — `TextBox` | **outdated** — dependency not gated; no example (`3000,9000,9090`) |
| `hostAddressLoopback` | bool, default `false`, **requires `networkingMode=mirrored`** | `:1150` — `ToggleSwitch` | **outdated** — dependency not gated |

## Keys documented outside the reference table

| Key | Documented | App state | Verdict |
|:---|:---|:---|:---|
| `systemDistro` | `[wsl2]`, `intune.md:25/56` only — no reference-table row | absent (`grep -rni "systemdistro" lib/` → 0 hits) | **missing, no action** — enterprise/system-distro plumbing, not a settings-screen key |
| `kernelDebugPort` | `[wsl2]`, `intune.md:29/60` only | absent (0 hits) | **missing, no action** — kernel debugging, same reasoning |

## Cross-cutting findings

These are not per-key gaps; they are properties of the editor and of the `.wslconfig`
read/write engine, and each one affects many keys at once.

### CC-1 — Boolean toggles display `false` for seven keys whose documented default is `true`

`settingsWidget`'s `SettingsType.bool` branch is
`checked: _settings[name]!.text == 'true'` (`settings_screen.dart:1208`). When a key is
absent from `.wslconfig` — the normal case — its controller text is empty, so the switch
renders **off** with an empty label. Affects `localhostForwarding`, `guiApplications`,
`nestedVirtualization`, `dnsProxy`, `firewall`, `dnsTunneling`, `autoProxy`; all seven
default to `true` per `wsl-config.md:225-246`. A user reading the screen concludes the
opposite of the truth for every one of them. Verdict **wrong**; the fix is a tri-state
(unset / on / off) or a "default: on" affordance, not a different initial `checked`.

### CC-2 — `readConfig` strips every space inside a value

`wsl.dart:623` (`value = value.replaceAll(' ', '')`) and the identical remote branch at
`:606`. Any `.wslconfig` value with an internal space is silently mangled on load, and
because `saveSettings` writes back every non-empty key
(`settings_screen.dart:271-286`), the mangled form is persisted the next time the user
presses Save. Concretely hits `kernelCommandLine`, and any `kernel` / `swapFile` path
under `C:\Program Files\…`. Verdict **wrong**.

### CC-3 — `readConfig` and `setConfig` are both section-blind

`readConfig` (`wsl.dart:596-630`) never tracks `[section]` headers — it flattens the whole
file into one `key → value` map. `setConfig` (`:544-592`) checks that `[$parent]` exists
and then runs `replaceAll(RegExp('$escapedKey[ ]*=(.*)'))` **across the entire file**, so a
key is rewritten wherever it appears, not inside the requested section. Three
consequences:

1. A key present under two sections collapses to one value on load.
2. Writing an `[experimental]` key rewrites a same-named key sitting under `[wsl2]`,
   leaving it in the wrong section.
3. `saveSettings` re-emits **every** key it loaded — including keys the app has no widget
   for — into `[wsl2]`, because `experimentalKeys` (`settings_screen.dart:271-279`) is a
   hardcoded list of the seven keys the app knows. A user's hand-added `[experimental]`
   key is relocated into `[wsl2]` on the next Save.

Verdict **wrong**. Contrast `getWSLConf` (`wsl.dart:1824`), which *does* track sections
correctly for `wsl.conf` — the correct parser already exists in the codebase.

### CC-4 — Key matching is case-sensitive; `.wslconfig` is not

`setConfig`'s regex is built from the camelCase spelling with no `caseSensitive: false`.
The docs' own example file (`wsl-config.md:280-320`) writes `swapfile=` and
`localhostforwarding=` all-lowercase. Against such a file the app does not find the key,
falls into the "add key value" branch, and **appends a duplicate** under `[wsl2]`.
Verdict **wrong**.

### CC-5 — Comment lines are parsed as keys

`readConfig` accepts any line containing `=`. A commented-out `# memory = 8GB` yields the
key `#memory`, which then round-trips through `saveSettings` → `setConfig`. Verdict
**wrong** (low impact, same fix as CC-3).

### CC-6 — Documented dependency graph is not honoured anywhere

Five "Only applicable when…" conditions are stated in `wsl-config.md`:

```
dnsTunneling=true       ──> bestEffortDnsParsing, dnsTunnelingIpAddress
autoProxy=true          ──> initialAutoProxyTimeout
networkingMode=mirrored ──> ignoredPorts, hostAddressLoopback
networkingMode=NAT      ──> dnsProxy
networkingMode=mirrored ──> localhostForwarding is IGNORED
```

No widget in `_buildGlobalConfigSettings` / `_buildExperimentalSettings` is disabled,
greyed, or annotated based on another key's value. Verdict **missing** (behaviour, not a
key).

### CC-7 — The "restart WSL" requirement is stated once, in a note the user must scroll past

`globalconfigurationinfo-text` (`en.json:117`) does carry the `wsl --shutdown` sentence,
and there is a **Stop WSL** button (`settings_screen.dart:168-185`, `stopwsl-text`) that
calls `WSLApi().restart()` — which runs `wsl --shutdown` twice (`wsl.dart:1169-1170`).
There is also an **Edit .wslconfig directly** button (`:152-163`). So the app is
**covered** here — better
than most. Two blemishes: the English string contains a stray comma
("Build 19041 and ,later"), and pressing **Save** does not offer to restart even though
*no* `.wslconfig` key takes effect without one. See [[features]].

### CC-8 — Orphaned i18n key

`unusedmemoryinfo-text` (`en.json:125`) describes `pageReporting`, a key that no longer
exists in the docs and is not rendered by the app (0 Dart references). Dead string in all
nine locale files. Verdict **outdated**, trivial cleanup.

## What was not examined

- **Runtime behaviour.** `wsl --version` was not run, no key was written to a real
  `.wslconfig` and observed taking effect, and no claim here is backed by execution. The
  Phase 04 runtime-verification task owns that; the version floors quoted above are the
  docs' annotations only.
- **`%UserProfile%\.wslconfig` on this machine** — not read.
- **The remote-WSL branches** of `setConfig`/`readConfig` (`wsl.dart:546-566`, `:597-614`)
  were read and carry the *same* CC-2/CC-3/CC-4 defects, but the SSH round-trip
  (`_readRemoteWslConfigText` / `_writeRemoteWslConfigText`) was not itself audited.
- **`writeConfig`** (`wsl.dart:534-541`) hard-codes a `[wsl2]` header and overwrites the
  whole file. It has no call site in `lib/` and was not analysed further.
- **Widget rendering** was read from source, not observed running. Slider bounds,
  toggle labels and the `memory` parse failure are inferred from the code path, not from
  a screenshot.
