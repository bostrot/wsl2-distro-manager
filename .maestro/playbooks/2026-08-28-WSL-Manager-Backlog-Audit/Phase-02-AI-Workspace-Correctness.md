# Phase 02: AI Workspace Correctness and Dead-Code Removal

This phase closes the remaining correctness items in `lib/api/ai_workspace/service.dart` and `lib/screens/ai_workspace_screen.dart` that the previous session recorded but did not fix: a failed install silently loses its error text, a card can read "Not installed" while still showing an `installPath` underneath, and Open WebUI is reported as running while its container is still migrating and cannot answer on its port. It also deletes the unreferenced `lib/components/navbar.dart`, which carries a stale `supportedLocales` list including `zh_HK` — a locale with no translation file, the exact pattern that blanks the entire app — and isolates the unexplained `bash: -c: line 2: syntax error near unexpected token '2'`.

Apply the repo conventions from Phase 01 (CRLF files, format only what you touch, append i18n keys without sorting, never add a locale without its file, use the theme colour helpers). Search `lib/` for an existing implementation before writing anything new.

## Tasks

- [x] Preserve the failure reason after a failed install in `lib/api/ai_workspace/service.dart`:
  - Today the post-install `refreshStatus()` re-probe overwrites `error` with `notInstalled` and clears `errorMessage`, so the user never gets to read why the install failed
  - Keep the `error` state and its `errorMessage` sticky until the next explicit user action (retry, install, start or an explicit dismiss), rather than until the next background probe
  - Make sure the existing "Retry" affordance (added 2026-08-27, `error` counts as installable) still works from that sticky state

  **Done (2026-08-28).** `ToolState.errorSticky` marks a failure that came from a
  *user action*. `_recordActionFailure()` sets it on every install/start failure
  path (including the `_ensureDockerReady()` ones); `refreshStatus()` returns
  early when it is set, only flipping `checked`/`hasKnownStatus` so the card
  still stops spinning. `clearError()` is the single release point and is called
  by `install()`, `start()`, `stop()`, `uninstall()` and the new dismiss button;
  it restores `status` from the last *confirmed* cached answer rather than
  guessing, since an error is never persisted. A probe-produced error is
  deliberately **not** sticky — a transient WSL hiccup must still be corrected by
  the next probe (covered by a test). The screen's `_handleInstall` now calls
  `_service.clearError(tool)` instead of hand-clearing the fields, so
  `canInstall` still sees `error` and the "Retry" label/enabled state is
  unchanged. Added an `X` (`FluentIcons.cancel`, reusing the existing
  `close-text` key — no new i18n) next to the error line, keyed
  `test-ai-dismiss-error-<tool>`, which clears and re-probes; without it a sticky
  failure had no way out. Five tests added in `test/ai_workspace_service_test.dart`.
  `flutter analyze` clean on the touched files, `flutter test` 313/313,
  `flutter test integration_test/ai_workspace_test.dart -d windows` 17/17.
  Note: `dart format` was **not** run — this repo predates the tall-style
  formatter and reformatting these files produces ~80 lines of unrelated churn.

- [x] Clear the stale `installPath` in `refreshStatus()` when a tool resolves to `notInstalled`, so a card can no longer read "Not installed" while showing `Installed: cmd://openclaw` underneath. Check every place `installPath` is assigned and make `notInstalled` the single point that resets it.

  **Done (2026-08-28).** Rather than patching the one `refreshStatus()` branch,
  `ToolState.status` became a getter/setter over a private `_status`, and the
  setter is now the *single* reset point: assigning `notInstalled` nulls
  `installPath`, everywhere, unconditionally. The constructor repeats the
  invariant so a freshly seeded state obeys it too. Audit of every assignment:
  `seedToolStates()` (cache seed — the `cachedStatus != null ? … : null`
  branch is gone, since a cached `notInstalled` now drops the path in the
  constructor), `_install()` success (sets `stopped` *then* the path — order
  matters, the setter only fires on `notInstalled`), `uninstall()` (its manual
  `installPath = null` was removed as redundant), and `refreshStatus()`'s three
  outcome branches plus the `_indicatesMissingDistro` branch. The `error` and
  docker-down branches deliberately leave the path alone — neither is a
  statement about installation.

  One complement was needed: because a `notInstalled` probe now clears the
  path, a later `running`/`exists` answer would otherwise leave the card with
  no `Installed:` line at all. `refreshStatus()` re-asserts
  `config.defaultInstallPath` on those two outcomes — legitimate, since
  `_existsCheck()` builds the probe from exactly that string, so an `exists`
  reply *is* a confirmation of that path. `_persistConfirmedState()` already
  removes the pref when the path is null, so the cache follows automatically.

  Three tests added to the `refreshStatus` group in
  `test/ai_workspace_service_test.dart`: stale path cleared on `notInstalled`,
  path re-asserted on a following `exists`, and a cached `notInstalled` not
  resurrecting a persisted path at seed time. `flutter analyze` clean on the
  touched files, `flutter test` 316/316,
  `flutter test integration_test/ai_workspace_test.dart -d windows` 17/17.
  `git diff --stat` is 2 files, no unrelated churn (`dart format` again not
  run, for the reason recorded above).

- [x] Add an Open WebUI health gate before the tool is reported as running:
  - The container needs ~2 minutes of alembic migrations before it becomes healthy, and probing or restarting it inside that window kills it (measured 2026-08-27)
  - Extend the Open WebUI `statusCheck` to consult `docker inspect --format {{.State.Health.Status}}` and only report `running` on `healthy`; surface `starting` as a distinct "starting up" state in the UI rather than as `running`
  - Keep the dashboard action disabled while the state is `starting`, and keep the existing "Dashboard URL not reachable from Windows" diagnostic as the fallback
  - Remember the shell-quoting rule: no double quotes in WSL command strings — `runInShell: false` means `"` reaches bash literally and breaks the filter

  **Done (2026-08-28).** New `ToolStatus.starting`, and a new optional
  `ToolConfig.healthCheck` — a second-stage probe that only runs once
  `statusCheck` says the tool is up, and must echo `running`, `starting` or
  `stopped`. Open WebUI's asks Docker: `docker inspect --format
  '{{.State.Health.Status}}'`, single-quoted (a `"` would reach bash literally
  under `runInShell: false`), compared with the `x$_h` idiom so an image with
  no `HEALTHCHECK` — empty answer, not evidence of a problem — falls through
  to `running` rather than stranding the card. `starting` → starting,
  `unhealthy` → stopped, everything else → running. Tools without a
  `healthCheck` are unchanged; the gate costs them nothing. `refreshStatus()`
  parses `starting` *before* `running`, and now also accepts a literal
  `stopped` (the unhealthy answer) so an up-but-unhealthy container cannot
  fall through to `notInstalled` and lose its install path.

  `start()` also had to be gated: `docker start` returns immediately, so the
  card claimed `running` for the whole migration window no matter what the
  probe said. A successful start on a tool with a `healthCheck` now re-probes
  before returning.

  UI: blue badge reading "Starting up…" (`startingup-text`, added to all nine
  locales with real translations, appended not sorted, CRLF preserved). The
  dashboard button is now *rendered but disabled* while starting, with a
  tooltip explaining why (`ai-workspace-startingup-hint-text`) — hiding it
  entirely reads as "this tool has no dashboard" rather than "not yet".
  `getUrl`/`getDashboardUrl` already return null for anything but `running`,
  so the "Dashboard URL not reachable from Windows" fallback is untouched.
  Start and Stop are keyed off `stopped`/`running` and so are both disabled
  while starting, which is what the "restarting inside the window kills it"
  measurement wants.

  **Blocker found and fixed: `wsl.exe` was flattening argv.** The gate could
  not work as specified, because `wsl.exe <args>` does not exec its command —
  it re-joins argv into one string and re-parses it through the distro's
  default shell, losing a quoting level. `bash -c '<script>'` arrived as
  `bash -c <first word>` with the rest running in the *outer* shell, so every
  `VAR=$(…)` in these command strings was silently lost. Measured live through
  Dart's `Process.run`: `bash -c 'X=hello; echo [$X]'` printed `[]`, and
  `$BASH_EXECUTION_STRING` came back as `bash -c echo …`. Consequences beyond
  this task: the probe's `_s=$(…)` was always empty, so `refreshStatus()`
  **never once took the `running` branch for any tool**, and `set -o pipefail`
  on installs never applied. `_wslArgs()` now passes `--exec`, which execs
  argv intact — verified live: old form returned `exists` plus
  `bash: line 1: [: =: unary operator expected`; new form returned `starting`
  mid-migration and `running` once healthy, with clean stderr.

  This is the root cause of the `bash: -c: line 2: syntax error near
  unexpected token '2'` item further down. It is written up in
  `Working/bash-line2-syntax-error.md` with two runnable reproductions
  (`Working/probe_repro.dart`, `Working/probe_live.dart`), but that task is
  **left unchecked**: the codebase-wide audit and the `AGENTS.md` constraint
  are still owed, and only `AiWorkspaceService` is fixed here.

  Nine tests added (`test/ai_workspace_service_test.dart`): starting while
  migrating, running once healthy, the probe consults `docker inspect` health
  with no double quotes, non-gated tools are untouched, unhealthy reads as
  stopped and keeps its path, a started Open WebUI stays starting,
  `getDashboardUrl` is null while starting, and `--exec` precedes `bash`.
  `flutter analyze` clean on the touched files, `flutter test` 324/324,
  `flutter test integration_test/ai_workspace_test.dart -d windows` 17/17,
  `dart run scripts/check_translations.dart` clean. `dart format` again not
  run, for the reason recorded above.

- [x] Make the OpenClaw and Hermes status checks reflect service health rather than process existence:
  - `pgrep -f '[o]openclaw'` / `pgrep -f '[h]ermes.*gateway'` only prove a process exists; the gateway was live while nothing listened on 18789
  - Probe the port (or use the tool's own `gateway status`) so a card cannot read "running" while the service is unusable
  - Reuse the existing `_firstServiceUrl` Dart-side parsing rather than adding shell-side `grep`/`$(...)`/redirection, which does not survive Dart's Windows argument escaping

  **Done (2026-08-28).** Half the premise was already stale: OpenClaw's
  `statusCheck` stopped being `pgrep` in `13652e6` and was already
  `ss -ltn | grep -q 18789`. Hermes was still `pgrep -f '[h]ermes.*gateway'`.
  Rather than porting the OpenClaw one-liner across, both tools now share one
  Dart-side helper trio, so the probe exists in exactly one place:
  `_listeningTest(port)` (a bash *condition*), `_listeningStatusCheck(port)`
  (the `ToolConfig.statusCheck` wrapper that echoes running/stopped) and
  `_waitForPort(port)` (the start gate). `_toolConfigs` became `final` instead
  of `const` so the entries can call them, and the ports are named
  (`_kHermesPort`, `_kOpenClawPort`) instead of appearing as three literals
  each. The twenty-iteration list is now one constant, `_kWaitIterations`,
  shared with the existing `_kDockerWaitLoop`.

  The probe is `ss -ltn | grep -qE ':<port>([^0-9]|$)'` with an
  `(exec 3<>/dev/tcp/127.0.0.1/<port>)` fallback. Two deliberate changes from
  the old OpenClaw line: the port is **anchored**, because a bare
  `grep -q 18789` also matches `:187890` and any other column carrying those
  digits; and the `/dev/tcp` fallback keeps an image without iproute2 from
  reporting every gateway as stopped forever, which the `ss`-only form would
  do silently.

  Start commands were gated too, not just the probe — otherwise `start()` sets
  `status = running` on a command whose success meant nothing. Hermes' trailing
  `sleep 1; pgrep …` became the shared port wait; OpenClaw's hand-rolled
  `for i in …` loop became the same helper. `start()` itself is unchanged: the
  command is now self-gating on the port, so a `true` return really does mean
  something is listening.

  A gateway that is alive but not listening now answers `stopped`, which sends
  `refreshStatus()` into the `_existsCheck()` branch — so it reads "Stopped"
  and keeps its `Installed: cmd://hermes` line, rather than falling through to
  `notInstalled` and losing the path.

  **Deviation from the third bullet, deliberate.** `_firstServiceUrl` parses a
  *URL* out of dashboard output; a port probe has no URL to parse, so there is
  nothing to reuse there — it stays the dashboard path's parser and is
  untouched. The bullet's stated rationale ("shell-side `grep`/`$(...)` does
  not survive Dart's Windows argument escaping") was root-caused in the
  previous task and is no longer true: it was `wsl.exe` flattening argv, fixed
  by `--exec` (see `Working/bash-line2-syntax-error.md`). Verified live against
  the real `ai-workspace` distro rather than assumed — `ss` is present there,
  a listening port returned `running`, a closed one `stopped`, and
  `grep -qE ':3338([^0-9]|$)'` correctly refused to match a socket on `:33387`.
  The `/dev/tcp` fallback was exercised separately in a shell with no `ss` and
  also returned `running` against an open port.

  Six tests added to `test/ai_workspace_service_test.dart` (port-not-pgrep for
  each gateway, port anchoring plus the no-double-quotes rule, not-listening
  reads as stopped and keeps its install path, and both start commands waiting
  on the port). `flutter analyze` 105 issues before and after — no new ones,
  none in the touched files. `flutter test` 330/330,
  `flutter test integration_test/ai_workspace_test.dart -d windows` 17/17.
  `git diff --stat` is 2 files, no unrelated churn. `dart format` again not
  run, for the reason recorded above.

- [x] Delete `lib/components/navbar.dart` after confirming nothing imports it:
  - Verify with `grep -rn "navbar" lib/ test/ integration_test/`
  - Delete the file, and delete any now-dead i18n keys or assets it alone referenced only if nothing else uses them
  - If any import does exist, instead fix its `supportedLocales` list to match `supportedLocalesList` exactly (drop `zh_HK` and bare `zh`) and record why the file was kept

  **Done (2026-08-28), deleted — no import exists.** `grep -rn "navbar" lib/
  test/ integration_test/` returns exactly 4 hits, all of them
  `lib/components/navbar.dart` naming its own `Navbar`/`_NavbarState`. Nothing
  imports it. Git confirms why: `29d9249` ("#256 Remove Navbar component and
  adjust NavigationPane size in RootPage") unwired it; the file was left behind
  and has been edited by drive-by refactors ever since — most recently
  `1b96bd2`, today — which is how it kept accumulating a stale locale list
  nobody could see. So the conditional branch does not apply and the file is
  gone rather than repaired.

  Audit of everything it declared, before deleting:
  - `Navbar`, `_NavbarState`, `navWidget`, `lockFor500Ms` — referenced only
    from inside the file. Its live replacement is `lib/nav/panelist.dart`,
    which builds the same eight pane items against the real router.
  - `WindowButtons` — a **duplicate**. `lib/nav/root_screen.dart:290` declares
    an identical class and is the one actually mounted (`root_screen.dart:219`).
    Deleting the navbar copy removes a same-named class from `lib/`, it does
    not remove the widget.
  - `hasPushed` — also a duplicate. The live one is
    `lib/components/helpers.dart:14`, which is what `settings_screen.dart`
    reads and writes; navbar's top-level copy was shadow state nothing could
    reach.
  - i18n: all eight keys it used (`homepage-text`, `about-text`,
    `settings-text`, `managequickactions-text`, `addinstance-text`,
    `mountdisk-text`, `documentation-text`, `sponsor-text`) are still used by
    `lib/nav/panelist.dart` and others, so **no key was orphaned** and no
    `lib/i18n/*.json` was touched. It referenced no assets.

  The dead `supportedLocales` list is therefore gone with the file rather than
  corrected: it listed `Locale('zh','HK')` and bare `Locale('zh','')`, and
  neither `zh_HK.json` nor `zh.json` exists in `lib/i18n/`. `main.dart:268`
  already uses `supportedLocalesList` from `lib/components/constants.dart`,
  which is the correct nine-entry list with a file for every entry, so the app
  never actually read the bad one — but it was the copy a future edit would
  have copied from.

  Two follow-ons: `AGENTS.md`'s `_solid`/`_fill` icon warning cited
  `heart_fill` in this file as its "dead code" example — reworded so the rule
  survives the file it pointed at. `TODO.md`'s Housekeeping entry is struck
  through with the outcome.

  Deliberately **not** touched: `doc/api/components_navbar/` (10 generated
  dartdoc pages). `doc/api` is a committed dartdoc snapshot; hand-deleting a
  subtree would leave `index.json` and the sidebar linking to removed pages,
  which is worse than a uniformly stale snapshot. It corrects itself on the
  next docs regeneration.

  Verification: `flutter analyze` 105 issues before **and** after — identical,
  no new issues, and the file contributed none. `flutter test` 330/330.
  Integration tests pass **per file** — `ai_workspace` 17/17, `app_test`
  21/21 (including "Complete navigation flow through all pages" and "App
  launches and renders home page"), `license_screen` 4/4, `byok_settings` 2/2,
  `mcp_settings` 2/2, 46 total. Running the whole `integration_test/` directory
  in one invocation still fails the 2nd–5th files with "Unable to start the app
  on the device" / "The log reader stopped unexpectedly"; that is the known
  launch-contention behaviour of back-to-back real-window runs, not a
  regression — every one of those files passes on its own, and there are no
  assertion failures anywhere in the batch log
  (`Working/phase-02-task05-integration.txt`). `git diff --stat` is 3 files,
  9 insertions / 334 deletions, no unrelated churn.

- [x] Isolate the `bash: -c: line 2: syntax error near unexpected token '2'` error:
  - It appeared when a start command containing `$(seq 1 20)` and subshell parentheses was added, and vanished when both were removed — yet identical constructs elsewhere in the same file work, and the error was reported by a user before those constructs existed, so "parentheses are mangled" is not sufficient
  - Write a focused reproduction under `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/` that sends escalating command strings through `ExecutionBroker` to a real distro and logs the exact argv that reaches `wsl.exe`
  - Identify the trigger (candidates: embedded newlines in the command string, Dart's Windows argument escaping, `runInShell` interaction) and record the finding in `Working/bash-line2-syntax-error.md`
  - Fix it if the cause is on our side; if it is a WSL/bash behaviour we must avoid, add the constraint to `AGENTS.md` and enforce it wherever long WSL command strings are built

  **Done (2026-08-28).** The root cause was isolated earlier, while doing the
  Open WebUI health gate above, because that gate could not work until it was
  understood: `wsl.exe` does not exec the command it is given — it re-joins
  its argv into one string and hands that to the distro's *default shell*,
  which parses it a second time and destroys one level of quoting. So
  `bash -c '<script>'` arrives as `bash -c <first word>` (a throwaway child)
  with the rest of the script running in the *outer* shell. When the string
  contains a newline, the outer shell's failed re-parse is what surfaces as
  `bash: -c: line 2: …` — which is why "parentheses are mangled" was never
  sufficient and why a user could hit it before `$(seq 1 20)` existed: the
  trigger is the *newline plus the re-parse*, not any particular construct.
  Write-up and two runnable reproductions were already in
  `Working/bash-line2-syntax-error.md`, `Working/probe_repro.dart`,
  `Working/probe_live.dart`.

  This session closed the three things that were still owed — the
  codebase-wide audit, the `AGENTS.md` constraint, and enforcement.

  **Enforcement.** Rather than sprinkling `--exec` around, the hand-rolled
  builder inside `AiWorkspaceService` was promoted to a shared module,
  `lib/api/wsl_args.dart`, which is now the single place in-distro `wsl`
  arguments are built: `wslExecArgs(distro, argv, user:)` for real argv and
  `wslShellArgs(distro, script, user:, shell:)` for a shell script handed to
  `bash -c` as **one** argument. Both emit `--exec`. The module carries the
  full explanation so the next reader does not have to rediscover it.

  **Audit — two call sites were genuinely broken, not merely fragile:**
  - `WSLApi.execCmdAsRoot()` appended `splitShellArgs(cmd)` to the argument
    list. The split strips the quotes, wsl.exe re-joins the pieces with
    spaces, and the distro's shell then parses the *unquoted* result. This is
    the path `WslMcpTools.wsl_run_command` uses to forward an MCP client's
    arbitrary command, so any client command with quoting, a pipe or a
    redirection was silently corrupted. It also passed `runInShell: true`, a
    second independent mangling layer — `cmd.exe /c` eats `&`, `|`, `<`, `>`
    and `^` before wsl.exe ever sees them. Now `wslShellArgs(...)` with
    `runInShell: false`.
  - `WSLApi.exec()`'s non-`passwd` branch, same split-then-rejoin defect, and
    demonstrably live rather than theoretical: `create_dialog.dart` feeds it
    `echo '$user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/wslsudo`, whose
    quotes the split removes, leaving a bare `(` for bash to reject — so the
    sudoers line was never actually written when creating a distro with a
    user. Now `wslShellArgs(...)`.

  Four more sites were correct only by luck (`getDefaultUserHome`,
  `getDefaultUser` already passed `-e`; `execCmds`' `tail -f` spawn and
  `runCmds`' `/bin/bash /tmp/wdmcmds` spawn re-join to something that happens
  to re-parse identically) and were converted to the builders for uniformity.

  **`WSLApi.start()` was deliberately left alone** — it is the one call site
  that *depends* on the re-parse. Its trailing `;/bin/sh` only becomes a
  second command because the default shell re-parses the flattened argv, and
  that is what keeps the terminal window open after `startCmd` finishes.
  Adding `--exec` would exec `;/bin/sh` as a literal argument. Commented in
  place, with a test asserting `--exec` stays absent. Also untouched, for the
  same "nothing to protect" reason: the interactive stdin-driven spawns
  (`startShell`, `execCmds`/`runCmds` first spawn), the terminal launches
  (`openBashrc`, `startVSCode`, `exec`'s `passwd` branch), and every
  host-level verb (`--list`, `--import`, `--mount`, …), where `--exec` is not
  even valid. `mount_service.dart` never sends a command into a distro;
  `lib/api/mcp/*` and `lib/components/sync.dart` make no direct `wsl.exe`
  call — the MCP tools route through `execCmdAsRoot`/`startShell` and are
  fixed transitively.

  **`AGENTS.md`** gained the rule under **WSL / Windows Subprocess Gotchas**:
  the flattening itself, "never build in-distro `wsl` args by hand — use the
  builders", "never `splitShellArgs()` and append the pieces", the list of
  legitimate exceptions, and the `runInShell: true` layer.

  **Known gap, recorded not hidden.** Remote WSL mode still flattens a *third*
  time inside `ssh` (`ssh host wsl -d X --exec bash -c '<script>'`), because
  `_buildRemoteArgs()` does not quote what it appends. `--exec` fixes the
  wsl.exe layer but not the ssh layer. Fixing it means shell-quoting every
  argument that helper emits, which touches every remote path
  (move/import/export/mount) and deserves its own task rather than being
  smuggled into this one. Written into `AGENTS.md` as a known gap and into
  the Remaining-work section of `Working/bash-line2-syntax-error.md`.

  14 tests added: `test/wsl_args_test.dart` (7, covering the builders — the
  script is never split, `--exec` precedes the shell, metacharacters survive)
  and a group of 7 in `test/wsl_test.dart` asserting each converted call site
  emits the right argv, that `execCmdAsRoot` no longer runs through `cmd.exe`,
  and that `start()` still does *not* get `--exec`. Two existing tests
  asserted the old shape and were updated: `test/mocks.dart`'s `sh -c`
  dispatch now also matches `bash -c` and reads the command off the last
  argument, and `wsl_mcp_tools_test.dart`'s argv expectation — the latter
  gained a case proving a client's quoting reaches the distro verbatim.
  `flutter analyze` 105 issues before **and** after, none in the touched
  files. `flutter test` 345/345,
  `flutter test integration_test/ai_workspace_test.dart -d windows` 17/17,
  `dart run scripts/check_translations.dart` clean. `git diff --stat` is 6
  files + 2 new, no unrelated churn. `dart format` again not run, for the
  reason recorded above.

- [x] Add or extend tests for the changed behaviour in `test/ai_workspace_service_test.dart`:
  - Failed install keeps `error` + `errorMessage` across a background refresh
  - `notInstalled` clears `installPath`
  - Open WebUI reports `starting` (not `running`) when `docker inspect` yields `starting`, and `running` on `healthy`
  - Port-based status returns `stopped` when the process exists but nothing is listening

  **Done (2026-08-28).** All four bullets already had a service-level test,
  added alongside the fixes themselves: sticky error across a refresh
  (`install` group), `notInstalled` clears `installPath` plus the re-assert and
  cached-seed complements, `starting`/`running` from the health gate, and a
  not-listening gateway reading as stopped while keeping its path. Rather than
  restate them, this task closed the gap those tests share: **every one of them
  feeds the mock shell a canned answer**, so they assert how the service *reads*
  a probe result and can say nothing about whether the probe produces the right
  result.

  That gap is where every bug in this phase actually lived. The probes are bash
  programs assembled from Dart string fragments — `[ -d "~/.hermes" ]` that
  never matched because `~` does not expand inside double quotes, `grep -q
  18789` that also matched `:187890`, and the `wsl.exe` argv flattening that
  made `_s=$(…)` permanently empty. A mock returning `'running'` sees none of
  them.

  New group `probe script semantics` (11 tests) runs **the exact string
  `refreshStatus` sends into the distro** — captured from
  `testShell.lastCommand.last`, not re-typed — under a real bash, stubbing the
  distro's commands with *shell functions*, which take precedence over `PATH`
  and so need no temp dir, no `chmod` and no `PATH` juggling that msys would
  mangle. Covered: a listening port reads `running` (both gateways); a process
  that exists while nothing listens reads `exists` — the literal fourth bullet,
  with `pgrep` stubbed to succeed to show what the old probe would have said;
  neither listening nor installed reads `missing`; `:187890` is not `:18789`;
  and for Open WebUI `starting`/`healthy`/`unhealthy`/no-HEALTHCHECK/not-up plus
  the `dockerdown` marker.

  Two file-scope helpers were added: `_locateBash()` (Git Bash, else WSL's
  `bash.exe` — the scripts are POSIX-only and reference no host paths; the group
  carries `skip:` when neither exists, so CI without bash stays green) and
  `_hostPortIsOpen()`, because the probe's `/dev/tcp` fallback makes a genuine
  connection attempt — the three "nothing is listening" tests call
  `markTestSkipped` rather than fail if a real service happens to hold 18789.

  **Verified the tests have teeth by mutation**, not by watching them pass:
  breaking the anchor (`[^0-9]` → `[^X]`) and the health gate (`xstarting` →
  `xstartingZ`) in `service.dart` made exactly the two intended new tests fail.
  The pre-existing `reports Open WebUI as starting while its container is
  migrating` **passed against the broken gate** — which is the concrete
  demonstration that this group covers something the canned-stdout tests
  cannot. Mutations reverted; `git diff` is the test file only.

  `flutter analyze` 105 issues before and after, none in the touched file
  (`flutter analyze test/ai_workspace_service_test.dart` clean). `flutter test`
  356/356 (was 345), `flutter test integration_test/ai_workspace_test.dart -d
  windows` 17/17. `git diff --stat` is 1 file, 242 insertions / 1 deletion (the
  `dart:io` import gained `Socket`) — no unrelated churn. `dart format` again
  not run, for the reason recorded above.

- [x] Run `flutter test` and `flutter analyze`, fix every failure, then launch the app with `.maestro/tools/launch.ps1 --dart-define=WSLM_FORCE_PRO=true` and click through the AI Workspace screen: capture `.maestro/screenshots/phase-02/` shots of the not-installed, installing, error-with-message and running states, and confirm no card shows a stale `Installed:` path.

  **Done (2026-08-28).** `flutter analyze` 105 issues, unchanged from the
  baseline every earlier task in this phase recorded — all `info`, plus the one
  pre-existing `test/mocks.dart:342` warning; none in the AI Workspace files.
  `flutter test` was 356/356 green before any change and is **360/360** after,
  with zero skips. (The three `probe script semantics` port tests skip
  themselves while something real holds 18789 — they did skip mid-session,
  because the click-through had the OpenClaw gateway listening. The final run
  was made with the port free so they actually executed.) No failure needed
  fixing; the two code changes below came out of the click-through, not the
  test run.

  **Click-through.** `launch.ps1 -Mode run -ForcePro -Width 1280 -Height 900`
  (the task text spells the raw `--dart-define`; the script's switch for it is
  `-ForcePro`, and `-Mode run` is required because the gate sits behind
  `kDebugMode`). Ten shots in `.maestro/screenshots/phase-02/`, every state
  reached by a real action against the real `ai-workspace` distro — nothing
  staged:
  - `01-not-installed.png` — Hermes "Nicht installiert", **no `Installed:`
    line**, beside OpenClaw and Open WebUI both showing theirs.
  - `02-installing.png` — spinner in the Install button, siblings disabled.
  - `03-error-with-message.png` — the real Hermes installer downloads Playwright
    chromium under its own 600s timeout and so overran the broker's 5-minute
    one. Card shows the full `TimeoutException` text, a red badge, an **enabled
    "Wiederholen"**, and the dismiss `×`. No `Installed:` line.
  - `04-error-persists-across-navigation.png` — the same error after leaving the
    page and coming back. Named for what it actually proves: `_initService`
    skips any tool already `checked`, so this is a page rebuild, not a probe.
    The sticky-through-a-probe path stays covered by the unit tests.
  - `05-running.png` — OpenClaw green/"läuft" after Start, dashboard action
    appearing.
  - `06-starting.png` — Open WebUI blue "Startet...", dashboard rendered but
    disabled. `docker inspect` confirmed `starting` at that moment.
  - `07-error-dismissed.png` — `×` releases Hermes back to "Nicht installiert",
    still with no path (the timed-out install left `/usr/local/lib/hermes-agent`
    behind but no `hermes` on PATH, so `notInstalled` is the correct answer).
  - `08-running-open-webui.png`, `09-final-all-stopped.png`.

  **Stale `Installed:` path: confirmed clean.** Across all ten shots no card
  ever showed "Nicht installiert" together with a path, including the two cases
  that used to produce it — a card that had just failed an install, and one
  dismissed back to not-installed. Both tools that *are* installed kept their
  path through stopped, starting, running and error.

  **Two defects found by the click-through, and fixed here.**
  1. *The toast contradicted the card.* `start()` raised
     `ai-workspace-started-text` ("Open WebUI läuft") **before** the health
     re-probe, so it announced "running" over a card correctly reading
     "Startet...". The notification now runs after the re-probe and picks its
     key from the resulting status. No new i18n key — the existing
     `ai-workspace-starting-text` reads correctly here.
  2. *`starting` was a terminal state in the UI.* Nothing on this page re-probes
     a tool once it is `checked`, and the only timer watches installs — so once
     the health gate answered `starting` the card sat there with Start, Stop and
     the dashboard all disabled until the user clicked something. Observed live:
     `docker inspect` reported `healthy` while the card still read "Startet...".
     Added `_syncStartingWatch()`, a 10s poll that runs only while some tool is
     `starting` and cancels itself as soon as none is — wired into
     `_initService` (including the re-entry case, where every tool is already
     `checked` and the probe loop does nothing), `_handleStart`, the dismiss
     handler and the install watch. Verified in the rebuilt app: Open WebUI went
     "Startet..." -> "läuft" on its own, with no interaction.

  Four tests added — two in `test/ai_workspace_service_test.dart` (the toast is
  now recorded into a list instead of swallowed) and three in a new
  `test/ai_workspace_screen_test.dart` (settles, stops polling, never starts a
  poll when nothing is starting). Both fixes were mutation-checked: breaking the
  key choice and stretching the poll interval each failed exactly the intended
  test and nothing else. `TestShell` moved from the service test into the shared
  `test/mocks.dart` rather than being duplicated for the screen test.
  `git diff --stat` is 5 files + 1 new, no unrelated churn; `dart format` again
  not run, for the reason recorded above.

  **A third defect was found and deliberately left unfixed** — see the new task
  below and `Working/pkill-self-kill.md`. It is a different bug class from the
  four card states this task was asked to verify, and it earns its own task
  rather than being smuggled into this one.

- [x] Stop `pkill -f` from killing the shell that runs it, in `lib/api/ai_workspace/service.dart`:
  - Found by the Phase 02 click-through, not by a test: OpenClaw's **Stop** reported failure with a bare, empty `Error:` line while the gateway had in fact stopped
  - `pkill -f` matches the command line of its own `bash -c` parent. The `[o]penclaw`/`[h]ermes` bracket idiom shields the *pattern*, but not a second unbracketed mention of the tool elsewhere in the same command string
  - `hermesAgent.startCommand` (`setsid hermes gateway` after the `pkill`) and `openClaw.stopCommand` (`openclaw gateway stop` before it) both self-kill; Hermes therefore cannot start at all. Reproductions and a suggested `_killByPattern()` helper are in `Working/pkill-self-kill.md`
  - Verify against the real distro, not only the mock — a canned stdout cannot show a shell that killed itself
  - Also make `stop()`'s failure branch fall back to a real message when `result.stderr` is empty, instead of rendering `Error:` with nothing after it

  **Done (2026-08-28).** `_killByPattern(pattern)` landed next to `_waitForPort`,
  with the two patterns pulled out as `_kHermesPattern` / `_kOpenClawPattern` so
  every site shares one spelling. It emits
  `for _p in $(pgrep -f '<pattern>'); do [ $_p = $$ ] || [ $_p = $PPID ] || kill
  $_p; done 2>/dev/null; true` — `pkill` has no "skip my own process tree" flag,
  so the filtering has to happen in the shell. The trailing `true` preserves the
  exit status the old `|| true` callers relied on. Two deviations from the
  suggestion in `Working/pkill-self-kill.md`: the double quotes are gone (pids
  are numeric, and this file's rule is single quotes only), and the `pgrep` must
  stay a *single* command — `$(pgrep …)` forks and execs `pgrep` directly, but
  `$(pgrep … | anything)` forks a real subshell that inherits the matching
  command line and becomes a target of the loop that spawned it.

  **A third self-killing site was found**, beyond the two in the note's table:
  the openclaw branch of `uninstall()`, whose `rm -f …/openclaw` and
  `npm uninstall -g openclaw` both sit after the `pkill`. It died before removing
  anything. The hermes uninstall branch is safe by luck — its `$HOME/.hermes`
  comes *after* the `gateway` in the pattern text, so `hermes.*gateway` cannot
  match — but it now uses the helper too rather than depending on word order.
  The note's table has been corrected.

  `stop()`'s failure branch now falls back to a new `ai-workspace-stop-failed-text`
  key (added to all nine locales; `check_translations` clean) when `result.stderr`
  is blank. Stop is the only lifecycle call with no toast of its own, so that
  card line is the entire feedback.

  **Verified against the real `ai-workspace` distro, not only the mock.** All
  five fixed commands print `REACHED_END` and exit 0; the `pkill` forms of both
  the OpenClaw stop and the OpenClaw uninstall still exit 15 (SIGTERM) with no
  output at all, which is what a canned stdout can never show.

  Five tests added to `test/ai_workspace_service_test.dart`: one static guard
  (no emitted command reaches for `pkill`, and every kill loop carries both
  guards), two for the stop message (empty stderr falls back, real stderr is
  kept), and four that run the *actual* emitted bash — three with a recording
  `kill` stub asserting only the decoy pid is targeted, and one with an
  unstubbed `kill` and a `pgrep` that hands the loop nothing but `$$`/`$PPID`,
  so a regressed filter genuinely takes the test shell down. Mutation-checked
  both ways: dropping the guards fails 5 tests, reverting to plain `pkill` fails
  5. One pre-existing assertion had to move with the code —
  `starting hermes waits for its port` banned the word `pgrep` outright; it now
  pins `pgrep` to exactly one occurrence, in the kill, and asserts the listening
  test is still the last thing the command runs.

  `flutter analyze` 105 issues before and after (unchanged baseline, none in the
  touched files), `flutter test` 367/367, `flutter test
  integration_test/ai_workspace_test.dart -d windows` 17/17. `git diff --stat` is
  12 files, no unrelated churn. `dart format` again not run, for the reason
  recorded at the top of this document. Added the gotcha to `AGENTS.md` under
  the WSL/subprocess section, since it is a shell trap rather than a WSL one and
  will otherwise be rediscovered.

- [ ] Format only the touched files, confirm `git diff --stat` shows no unrelated churn, and commit the AI Workspace correctness fixes and the `navbar.dart` removal on `beta`.
