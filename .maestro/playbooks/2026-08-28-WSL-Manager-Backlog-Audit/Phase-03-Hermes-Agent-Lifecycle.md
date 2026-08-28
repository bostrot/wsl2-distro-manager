# Phase 03: Hermes Agent Lifecycle — Verify End to End and Fix

OpenClaw and Open WebUI were both verified working through the UI on 2026-08-27; Hermes Agent was not, because its installer runs past 10 minutes and never returns. The app's failure path is already correct (timeout → error card → full detail → enabled Retry), so this phase is about the installer itself and the rest of the lifecycle. The goal is a Hermes card whose install, start, stop and dashboard actions all work by clicking in the running app — or, if upstream genuinely cannot complete unattended, a long-running install with visible streamed progress rather than a silent five-minute wall.

Run the app with `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true` (the debug-only gate added in Phase 01) so the Pro-gated AI Workspace is reachable without the forbidden `return true;` hack. Apply the Phase 01 repo conventions throughout.

## Tasks

- [x] Diagnose the hanging installer before changing any app code:
  - In the `ai-workspace` distro, run `curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /tmp/hermes-install.sh` and read the script rather than piping it
  - Determine what it blocks on: a TTY prompt despite `--non-interactive`, a package manager waiting on a lock, an interactive `sudo`, or a long unbuffered download
  - Run it with `bash -x /tmp/hermes-install.sh --non-interactive` under `timeout 900` and capture the trace to `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/hermes-install-trace.log`
  - Write the conclusion to `Working/hermes-install-findings.md` including the exact line it stalls on

  **Result (2026-08-28, live against the real `ai-workspace` distro — Ubuntu 26.04, root):**
  The installer does not block at all. It completes unattended, exit 0, in **482 s cold**
  and **92 s warm**. The app allows **5 minutes** total wall clock
  (`lib/api/ai_workspace/service.dart:614`), so it kills a healthy install ~200 s early,
  always mid-`npm install` — which matches the debris found in the distro (repo cloned,
  467 MB uv cache, 656 MB Playwright cache, 357 MB npm cache, but no `hermes` binary).
  None of the four suspects applies: `prompt_yes_no()` short-circuits on `--non-interactive`
  before touching `read`/`/dev/tty`; the only raw `read` is `[ -t 0 ]`-guarded; the distro is
  root so no `sudo` path is reachable; apt is a single 5 s `update` with no lock wait.
  The stall is `hermes-install.sh:2428`,
  `run_with_timeout "$NODE_DEPS_TIMEOUT" npm install --silent >"$npm_log" 2>&1`
  (`NODE_DEPS_TIMEOUT` defaults to 600) — **306 s of complete silence** on the cold run,
  because `--silent` plus the unconditional redirect to a `mktemp` file means nothing is
  emitted unless the command fails. Second-largest is Playwright Chromium at 108 s
  (184.3 + 114.7 MiB behind `\r` progress bars). Ubuntu 26.04 also trips
  `playwright_host_unrecognized()`, so the 600 s Playwright step can retry once → 1200 s.
  **Any silence-based timeout must therefore exceed 600 s.** `hermes` v0.20.6 is now
  installed and on PATH. Gating the tool is not warranted.
  Written up in `Working/hermes-install-findings.md`; traces in
  `Working/hermes-install-trace.log` (the verbatim `timeout 900 bash -x` run, warm) and
  `Working/hermes-install-trace-cold.log` (same command with every cache wiped, timestamped
  per line — `bash` ignores an inherited `PS4` for non-interactive scripts, so a
  `stdbuf -oL awk` reader stamps them instead).

- [x] Make the Hermes install path survive a genuinely slow installer, in `lib/api/ai_workspace/service.dart`:
  - Switch the install from the one-shot capture path to `ExecutionBroker.startPersistent`/streaming so output arrives live (the Phase 01 broker rework guarantees the child is killed if it really does need to be abandoned)
  - Raise the Hermes install timeout to a value justified by the measurement above, and make the timeout apply to *silence* (no new output for N minutes) rather than total wall-clock, so a slow-but-progressing install is not killed
  - Add `set -o pipefail` wherever a `curl … | bash` shape remains — `curl … | sh` exits 0 when curl fails
  - Keep every command string free of double quotes, and avoid `~` inside double quotes (`[ -d "~/.foo" ]` never matches)

  **Result (2026-08-28):** Done in `lib/api/ai_workspace/service.dart`.
  `_install()` no longer calls `ExecutionBroker.run()`; it goes through a new
  `_runStreamed()`, which spawns the install with
  `ExecutionBroker.startPersistent`, reads both pipes live
  (`ExecutionBroker.decodeWslOutput`, so UTF-16LE is handled the same way
  everywhere), and reports every completed line through an `onLine` callback.
  `\r` terminates a line as well as `\n`, so Playwright's progress-bar
  redraws register as progress rather than as one 108 s silence.
  **The budget is silence, not wall clock:** `_kInstallSilenceTimeout` =
  12 min with nothing on *either* stream — above the 600 s the upstream script
  allows its own `npm install`/Playwright steps, which is what the measurement
  in the previous task requires — with `_kInstallMaxDuration` = 45 min as an
  absolute ceiling for an installer that wedges while still dribbling output.
  Both are constructor-injectable (`installSilenceTimeout`,
  `installMaxDuration`) purely as a test seam. Every abandon path reaps the
  child through `ExecutionBroker.terminate()` (made public for this; it was
  already the escalation `run()` used), so a give-up cannot leave an orphaned
  `wsl.exe` behind, and the resulting `errorMessage` names the budget that
  expired *and* the last line printed, since a killed shell writes nothing to
  stderr of its own.
  The `set -o pipefail;` prefix is unchanged and still applies to every
  install command — the two `curl … | bash` shapes are the whole reason it is
  there. A new test asserts no built command string contains a `"` or a `~`;
  none does.
  Progress is exposed as `installProgress(tool)` (last line, kept after the
  install ends, cleared when a retry starts) for the UI task that follows;
  no screen changes here.
  Tests added to `test/ai_workspace_service_test.dart` (group
  `streamed install`, 5 cases + the quoting guard): output is readable while
  the child is still running, the silence timeout fires and reaps, it does
  **not** fire while output keeps arriving across 3× the budget, the ceiling
  stops a chatty-but-endless installer, and a killed install stays `error`
  with its message intact through the next `refreshStatus()`. They need a
  child a test can drive, so `test/mocks.dart` gains `ControlledProcess` and
  `TestShell.processFactory`. `flutter analyze` is unchanged at 105 issues
  (all pre-existing) and `flutter test` is green at 373 (was 367).
  Formatting was scoped to the touched lines using the Phase 01 helper; note
  it needs a **`-U0`** diff — a diff with context makes it drop the context
  lines. `Working/revert_hunks.dart` is the repair path if that happens again.

- [x] Surface install progress in `lib/screens/ai_workspace_screen.dart`:
  - Show the last streamed output line (or a small scrolling log region) under the installing card, reusing whatever progress/log widget already exists in the repo rather than inventing one — search `lib/components/` first
  - Keep the existing "install survives navigation" behaviour intact: tracking lives in the service via `isInstalling()`, and `refreshStatus()` must not clobber an install in flight
  - Add any new i18n keys to **all** files in `lib/i18n/` by appending (never sorting), with real translations, not English placeholders

  **Result (2026-08-28):** Done in `lib/screens/ai_workspace_screen.dart`.
  The card now carries a progress region fed by `installProgress(tool)`: while
  `isInstalling(tool)` is true it shows the last streamed line, falling back to
  `ai-workspace-install-progress-text` until the installer prints anything, so
  the region does not pop into existence on the first line. **Nothing new was
  invented for it** — `lib/components/` has no log or progress widget (only
  `Notify`'s bottom InfoBar and bare `ProgressRing`s), so the page's own
  `_buildInlineStatus()` (spinner + grey secondary label) is reused, gaining a
  `fill` flag that takes the full width and ellipsises instead of sizing to the
  text; installer lines are arbitrarily long and would otherwise overflow the
  card. After a *failed* install the retained last line is shown as
  `Last output: …` — the service keeps it for exactly this reason, and for a
  silence-timeout kill it is the only clue there is, since a signalled shell
  writes nothing to stderr of its own.
  **The repaint problem was the real work.** Tracking still lives entirely in
  the service, and `refreshStatus()` still refuses to probe a tool that is
  installing — but the old `_watchOngoingInstalls()` only ticked for an install
  *inherited* from a previous instance of the page, and only called `setState`
  when one *finished*, so a line that changed every few seconds would never
  have been drawn. It is now `_syncInstallWatch()`: it repaints every second
  (`_kInstallProgressPoll`) while any install is in flight, reads a finished
  tool's real status back, and cancels itself when `_watchedInstalls` empties.
  `_handleInstall()` starts it from the button press — `install()` marks the
  tool installing before its first `await`, so the ticker can start on the same
  frame.
  Two keys appended to all nine `lib/i18n/*.json` with real translations
  (`ai-workspace-install-progress-text`, `ai-workspace-install-last-output-text`);
  `dart run scripts/check_translations.dart` is clean. Note for future edits:
  **`sed -i` in this git-bash strips every CR from the file it rewrites**, which
  silently turns a CRLF JSON file into LF and drops the substitution — use
  `perl -i -0777` (verified to preserve CRLF) for these files.
  Test-only keys added while here: the install/start/stop `FilledButton`s had
  none, so nothing could click them; they are now
  `test-ai-{install,start,stop}-<tool>`, unique per card as the repo requires.
  3 widget tests added to `test/ai_workspace_screen_test.dart` — output visible
  and *updating* mid-install with no user interaction, a fresh page re-attaching
  to an install started with no page mounted (and not probing over it), and a
  failed install keeping its last output on the card. Two harness findings that
  cost most of the time: `ControlledProcess` used **broadcast** controllers,
  which drop anything written before a listener attaches (now single-
  subscription, like a real pipe); and `StreamSubscription.cancel()` on a closed
  `StreamController` **never completes under the widget-test fake clock**, so
  `_runStreamed`'s cleanup stranded every UI-driven install — `pumpInstallToEnd()`
  waits under `tester.runAsync()` instead. `pumpAndSettle()` is unusable on this
  page at all: a `starting` tool's 10 s poll schedules a frame forever.
  `flutter test` 376 green (was 373), `flutter analyze` unchanged at 105
  pre-existing issues; formatting scoped to the touched lines with the Phase 01
  `-U0` helper. Logs in `Working/phase-03-task03-full-test.txt` and
  `Working/phase-03-task03-analyze.txt`.

- [x] Verify the Hermes lifecycle by clicking through the running app, capturing a screenshot at each step into `.maestro/screenshots/phase-03/`:
  - Install → progress visible, completes or fails with a readable reason
  - Start → card reports running only when the gateway is actually serving (port-based check from Phase 02)
  - Open dashboard → browser opens on a working Hermes page, not a documentation link
  - Stop → card returns to installed/stopped, and no `wsl.exe` orphans accumulate (`(Get-Process wsl).Count` before and after)
  - Record each result in `Working/hermes-clickthrough.md` with the screenshot filename next to it

  **Result (2026-08-28).** Done against the real `ai-workspace` distro,
  `launch.ps1 -Mode run -ForcePro -Width 1280 -Height 900`. 24 screenshots in
  `.maestro/screenshots/phase-03/`, full write-up with nine findings in
  `Working/hermes-clickthrough.md`. Nothing was staged and nothing was fixed
  here — the fixes belong to the next task, which now has an exact list.

  **The lifecycle does not work, and the cause is a single wrong assumption:**
  `hermes gateway` is the **messaging** gateway (Telegram/Discord/WhatsApp) and
  binds **no TCP port at all**. The thing that listens on 9119 is
  `hermes serve` / `hermes dashboard` (`--port PORT   Port (default 9119…)`).
  The port constant is right; the command aimed at it is not. Started
  `hermes serve --skip-build` by hand and the card went green on its own with
  `http://localhost:9119` answering **HTTP 200** from Windows
  (`19-running-after-serve.png`) — so the Phase 02 port-based check needs no
  change.

  - **Install — fails, but the streaming works.** Progress is visible and
    updates with no interaction across seven screenshots. It dies at
    `Nothing was printed for 12 min, so the command was stopped.` The budget
    did **not** misfire: `hermes_cli.main setup` was wedged with **`fd 0 →
    /dev/tty`**, zero `/proc/<pid>/io` movement over 30 s and no log line for
    20 min — an interactive prompt (cf. `--accept-hooks`, *"without a TTY
    prompt"*). Task 01's 482 s unattended run only completed because it had a
    real terminal. Upstream `uv sync --locked` also errors on a stale
    `uv.lock`, non-fatally, and dominates the failure tail. Two rendering
    defects: ANSI escapes survive as `[0;36m` residue, and the `\r`-split
    Playwright bar leaves the frozen fragment `(O) 2. No` as both the progress
    line and the retained "last output".
  - **Start — fails with a bare `Error:`** and no text (the empty-stderr
    fallback Phase 02 added to `stop()` was never added to `start()`), plus the
    stale *install* progress line on a *start* failure.
  - **Open dashboard — never opens.** `hermes dashboard` starts a server and
    blocks; it prints no URL, so the card says
    `No dashboard URL from: hermes dashboard`. Browser process count 15 → 15.
  - **Stop — reports success while the service is still serving.** `stop()`
    trusts exit 0, and the command ends in `; true`; `hermes serve` was still
    running and still listening on 9119 with the card reading "angehalten".
  - **Orphans — clean.** `(Get-Process wsl).Count` 2 before and 2 after the
    whole cycle (both the keep-alive), and it dropped to 0 the moment the
    silence timeout reaped the abandoned install. Force-killing the app does
    leak those 2 keep-alive processes.
  - **Two defects outside the four bullets.** Uninstall reports success but
    leaves `/usr/local/bin/hermes` — a wrapper *script*, not a symlink — so the
    card still reads "Installed" over a tool that cannot run, and the app can
    never return itself to a clean state. And on the first launch of a session a
    cached status renders with no "checking" indicator, so two installed tools
    read "Nicht installiert" for 14 s; the probe itself is sound
    (`Working/probe_hermes.dart` replicates it and always answers `exists`).

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
