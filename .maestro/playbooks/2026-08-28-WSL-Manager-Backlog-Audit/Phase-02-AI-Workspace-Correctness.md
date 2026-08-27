# Phase 02: AI Workspace Correctness and Dead-Code Removal

This phase closes the remaining correctness items in `lib/api/ai_workspace/service.dart` and `lib/screens/ai_workspace_screen.dart` that the previous session recorded but did not fix: a failed install silently loses its error text, a card can read "Not installed" while still showing an `installPath` underneath, and Open WebUI is reported as running while its container is still migrating and cannot answer on its port. It also deletes the unreferenced `lib/components/navbar.dart`, which carries a stale `supportedLocales` list including `zh_HK` — a locale with no translation file, the exact pattern that blanks the entire app — and isolates the unexplained `bash: -c: line 2: syntax error near unexpected token '2'`.

Apply the repo conventions from Phase 01 (CRLF files, format only what you touch, append i18n keys without sorting, never add a locale without its file, use the theme colour helpers). Search `lib/` for an existing implementation before writing anything new.

## Tasks

- [ ] Preserve the failure reason after a failed install in `lib/api/ai_workspace/service.dart`:
  - Today the post-install `refreshStatus()` re-probe overwrites `error` with `notInstalled` and clears `errorMessage`, so the user never gets to read why the install failed
  - Keep the `error` state and its `errorMessage` sticky until the next explicit user action (retry, install, start or an explicit dismiss), rather than until the next background probe
  - Make sure the existing "Retry" affordance (added 2026-08-27, `error` counts as installable) still works from that sticky state

- [ ] Clear the stale `installPath` in `refreshStatus()` when a tool resolves to `notInstalled`, so a card can no longer read "Not installed" while showing `Installed: cmd://openclaw` underneath. Check every place `installPath` is assigned and make `notInstalled` the single point that resets it.

- [ ] Add an Open WebUI health gate before the tool is reported as running:
  - The container needs ~2 minutes of alembic migrations before it becomes healthy, and probing or restarting it inside that window kills it (measured 2026-08-27)
  - Extend the Open WebUI `statusCheck` to consult `docker inspect --format {{.State.Health.Status}}` and only report `running` on `healthy`; surface `starting` as a distinct "starting up" state in the UI rather than as `running`
  - Keep the dashboard action disabled while the state is `starting`, and keep the existing "Dashboard URL not reachable from Windows" diagnostic as the fallback
  - Remember the shell-quoting rule: no double quotes in WSL command strings — `runInShell: false` means `"` reaches bash literally and breaks the filter

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

- [ ] Add or extend tests for the changed behaviour in `test/ai_workspace_service_test.dart`:
  - Failed install keeps `error` + `errorMessage` across a background refresh
  - `notInstalled` clears `installPath`
  - Open WebUI reports `starting` (not `running`) when `docker inspect` yields `starting`, and `running` on `healthy`
  - Port-based status returns `stopped` when the process exists but nothing is listening

- [ ] Run `flutter test` and `flutter analyze`, fix every failure, then launch the app with `.maestro/tools/launch.ps1 --dart-define=WSLM_FORCE_PRO=true` and click through the AI Workspace screen: capture `.maestro/screenshots/phase-02/` shots of the not-installed, installing, error-with-message and running states, and confirm no card shows a stale `Installed:` path.

- [ ] Format only the touched files, confirm `git diff --stat` shows no unrelated churn, and commit the AI Workspace correctness fixes and the `navbar.dart` removal on `beta`.
