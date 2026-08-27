# Phase 03: Hermes Agent Lifecycle — Verify End to End and Fix

OpenClaw and Open WebUI were both verified working through the UI on 2026-08-27; Hermes Agent was not, because its installer runs past 10 minutes and never returns. The app's failure path is already correct (timeout → error card → full detail → enabled Retry), so this phase is about the installer itself and the rest of the lifecycle. The goal is a Hermes card whose install, start, stop and dashboard actions all work by clicking in the running app — or, if upstream genuinely cannot complete unattended, a long-running install with visible streamed progress rather than a silent five-minute wall.

Run the app with `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true` (the debug-only gate added in Phase 01) so the Pro-gated AI Workspace is reachable without the forbidden `return true;` hack. Apply the Phase 01 repo conventions throughout.

## Tasks

- [ ] Diagnose the hanging installer before changing any app code:
  - In the `ai-workspace` distro, run `curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /tmp/hermes-install.sh` and read the script rather than piping it
  - Determine what it blocks on: a TTY prompt despite `--non-interactive`, a package manager waiting on a lock, an interactive `sudo`, or a long unbuffered download
  - Run it with `bash -x /tmp/hermes-install.sh --non-interactive` under `timeout 900` and capture the trace to `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/hermes-install-trace.log`
  - Write the conclusion to `Working/hermes-install-findings.md` including the exact line it stalls on

- [ ] Make the Hermes install path survive a genuinely slow installer, in `lib/api/ai_workspace/service.dart`:
  - Switch the install from the one-shot capture path to `ExecutionBroker.startPersistent`/streaming so output arrives live (the Phase 01 broker rework guarantees the child is killed if it really does need to be abandoned)
  - Raise the Hermes install timeout to a value justified by the measurement above, and make the timeout apply to *silence* (no new output for N minutes) rather than total wall-clock, so a slow-but-progressing install is not killed
  - Add `set -o pipefail` wherever a `curl … | bash` shape remains — `curl … | sh` exits 0 when curl fails
  - Keep every command string free of double quotes, and avoid `~` inside double quotes (`[ -d "~/.foo" ]` never matches)

- [ ] Surface install progress in `lib/screens/ai_workspace_screen.dart`:
  - Show the last streamed output line (or a small scrolling log region) under the installing card, reusing whatever progress/log widget already exists in the repo rather than inventing one — search `lib/components/` first
  - Keep the existing "install survives navigation" behaviour intact: tracking lives in the service via `isInstalling()`, and `refreshStatus()` must not clobber an install in flight
  - Add any new i18n keys to **all** files in `lib/i18n/` by appending (never sorting), with real translations, not English placeholders

- [ ] Verify the Hermes lifecycle by clicking through the running app, capturing a screenshot at each step into `.maestro/screenshots/phase-03/`:
  - Install → progress visible, completes or fails with a readable reason
  - Start → card reports running only when the gateway is actually serving (port-based check from Phase 02)
  - Open dashboard → browser opens on a working Hermes page, not a documentation link
  - Stop → card returns to installed/stopped, and no `wsl.exe` orphans accumulate (`(Get-Process wsl).Count` before and after)
  - Record each result in `Working/hermes-clickthrough.md` with the screenshot filename next to it

- [ ] Fix whatever the click-through breaks. Likely candidates, all previously seen on the sibling tools:
  - The gateway dying with its WSL session — `AiWorkspaceService` already holds one `wsl -d ai-workspace sleep infinity` session via `ExecutionBroker.startPersistent`; confirm Hermes is covered by it, since Hermes uses the `setsid` shape and may not need it
  - Dashboard URL extraction happening shell-side; parse in Dart via the existing `_firstServiceUrl` helper, preferring a loopback address
  - `canLaunchUrl` gating the launch — every other launch site in the app calls `launchUrl` directly

- [ ] If and only if the installer proves impossible to complete unattended after the fixes above, gate the tool rather than shipping a broken card:
  - Mark Hermes as unavailable in the tool list with a short explanatory string and a link to the upstream issue
  - Keep the code path intact behind the gate so it can be re-enabled with a one-line change
  - Document the decision and the evidence in `Working/hermes-install-findings.md` and add a line to `TODO.md`

- [ ] Add tests to `test/ai_workspace_service_test.dart` covering the new install semantics: silence-based timeout fires when no output arrives, does **not** fire while output keeps coming, and a killed install leaves the service in `error` with its message intact.

- [ ] Run `flutter test` and `flutter analyze`, fix all failures, format only the touched files, and commit the Hermes lifecycle work on `beta`. Update the Hermes sections of `TODO.md` to reflect the verified state.
