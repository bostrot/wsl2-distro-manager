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

- [ ] Make the OpenClaw and Hermes status checks reflect service health rather than process existence:
  - `pgrep -f '[o]openclaw'` / `pgrep -f '[h]ermes.*gateway'` only prove a process exists; the gateway was live while nothing listened on 18789
  - Probe the port (or use the tool's own `gateway status`) so a card cannot read "running" while the service is unusable
  - Reuse the existing `_firstServiceUrl` Dart-side parsing rather than adding shell-side `grep`/`$(...)`/redirection, which does not survive Dart's Windows argument escaping

- [ ] Delete `lib/components/navbar.dart` after confirming nothing imports it:
  - Verify with `grep -rn "navbar" lib/ test/ integration_test/`
  - Delete the file, and delete any now-dead i18n keys or assets it alone referenced only if nothing else uses them
  - If any import does exist, instead fix its `supportedLocales` list to match `supportedLocalesList` exactly (drop `zh_HK` and bare `zh`) and record why the file was kept

- [ ] Isolate the `bash: -c: line 2: syntax error near unexpected token '2'` error:
  - It appeared when a start command containing `$(seq 1 20)` and subshell parentheses was added, and vanished when both were removed — yet identical constructs elsewhere in the same file work, and the error was reported by a user before those constructs existed, so "parentheses are mangled" is not sufficient
  - Write a focused reproduction under `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/` that sends escalating command strings through `ExecutionBroker` to a real distro and logs the exact argv that reaches `wsl.exe`
  - Identify the trigger (candidates: embedded newlines in the command string, Dart's Windows argument escaping, `runInShell` interaction) and record the finding in `Working/bash-line2-syntax-error.md`
  - Fix it if the cause is on our side; if it is a WSL/bash behaviour we must avoid, add the constraint to `AGENTS.md` and enforce it wherever long WSL command strings are built

  **Root cause already found (2026-08-28), task still open.** Isolated while
  doing the Open WebUI health gate above, because that gate could not work
  until it was understood. `wsl.exe` re-joins argv and re-parses it through
  the distro's default shell, so `bash -c '<script>'` loses a quoting level;
  `--exec` fixes it. Full write-up and two runnable reproductions:
  `Working/bash-line2-syntax-error.md`, `Working/probe_repro.dart`,
  `Working/probe_live.dart`. **Still owed here:** the audit of every other
  `wsl.exe` call site (`lib/api/wsl.dart`, `mount_service.dart`, `mcp/`,
  `components/sync.dart`), the `AGENTS.md` constraint, and enforcement
  wherever long WSL command strings are built. Only
  `AiWorkspaceService._wslArgs()` is fixed so far.

- [ ] Add or extend tests for the changed behaviour in `test/ai_workspace_service_test.dart`:
  - Failed install keeps `error` + `errorMessage` across a background refresh
  - `notInstalled` clears `installPath`
  - Open WebUI reports `starting` (not `running`) when `docker inspect` yields `starting`, and `running` on `healthy`
  - Port-based status returns `stopped` when the process exists but nothing is listening

- [ ] Run `flutter test` and `flutter analyze`, fix every failure, then launch the app with `.maestro/tools/launch.ps1 --dart-define=WSLM_FORCE_PRO=true` and click through the AI Workspace screen: capture `.maestro/screenshots/phase-02/` shots of the not-installed, installing, error-with-message and running states, and confirm no card shows a stale `Installed:` path.

- [ ] Format only the touched files, confirm `git diff --stat` shows no unrelated churn, and commit the AI Workspace correctness fixes and the `navbar.dart` removal on `beta`.
