# TODO

Working list for WSL Distro Manager. Longer background lives in
`SESSION-HANDOFF.md`.

---

## Done 2026-08-27 (uncommitted)

- [x] **New-instance dialog is now a dedicated screen** — `lib/screens/create_screen.dart`,
      route `/addinstance`. All three entry points (sidebar, home button, navbar)
      navigate instead of opening the dialog. Verified in the running app.
- [x] **Docker readiness** — `refreshStatus()` and `_ensureDockerReady()` both wait
      for `docker info` (shared `_kDockerWaitLoop`). An unreachable daemon now
      reports `dockerdown` and keeps the last confirmed status instead of
      silently caching `notInstalled`.
- [x] **Install survives navigation** — tracking moved into the service
      (`isInstalling()`); `refreshStatus()` will not clobber an install in
      flight. Verified live: navigating away and back keeps the spinner.
- [x] **Retry from the error state** — `error` counts as installable, button
      reads "Retry". Previously it was greyed out and mislabelled "Installed",
      stranding the user. Verified live.
- [x] **Shell quoting** — every double quote removed from the WSL command
      strings. `runInShell: false` means Dart escapes each arg for the Windows
      command line and `"` reaches bash literally, which broke
      `docker ps --filter "name=..."`, the dashboard command, and made
      `pgrep -f "[o]penclaw"` always report "stopped".
- [x] **Distro creation** — `wsl --install` exits non-zero even when it
      succeeds (it also tries an interactive first-boot). Now verified by
      listing; the error message falls back to stdout instead of a bare colon.
- [x] **msix declares es/hu/ja** — `pubspec.yaml` languages now matches
      `supportedLocalesList`, so those Store listings become possible.

---

## Now

### ExecutionBroker leaks a process on every timeout — highest priority
`lib/api/execution/broker.dart` ~110–124:

```dart
final ProcessResult result = await _shell.run(...).timeout(
  request.timeout,
  onTimeout: () => throw TimeoutException('Command timed out after ...'),
);
```

The timeout throws but **never kills the child**. `Process.run` hands back no
handle, so the abandoned `wsl.exe` lives forever. `list.dart` re-polls every 5
seconds, so once WSL starts hanging the orphans accumulate without limit.

Measured on 2026-08-27: **842 orphaned `wsl.exe` processes**, enough that WSL
stopped responding entirely and even `wsl --shutdown` timed out. Killing them
restored it immediately.

Fix: route the non-streaming path through `Shell.start` (already used at
~line 197 for streaming, and `Process` exposes `kill()`), collect
stdout/stderr, and kill the process in the timeout handler. Note
`execution_broker_test.dart` mocks `Shell.run`, so those tests need updating
too.

### Keep-alive survives a hard kill of the app
`dispose()` releases the held `wsl … sleep infinity` session on a clean exit,
but a force-kill (Task Manager, `Stop-Process -Force`) skips provider disposal
and the process lingers, holding the distro up. Harmless but untidy —
`wsl --shutdown` clears it. Consider a Windows job object so children die with
the parent, which would also bound the `ExecutionBroker` process leak below.

### ~~Open WebUI~~ — WORKS, verified through the UI 2026-08-27
Install, start, stop and dashboard all verified by clicking in the app. Edge
opened `localhost:8083` on the Open WebUI welcome page.

The earlier "exit 255" crashes were **first-run only**: the container needs
~2 minutes to finish migrations and become healthy, and it exits if probed or
restarted during that window. Once healthy it stays up (`Up (healthy)`,
ExitCode=0). A dashboard click during startup correctly reported
*"Dashboard URL not reachable from Windows: http://localhost:8083"* — the new
diagnostic message doing its job.

Worth considering: wait for `docker inspect --format {{.State.Health.Status}}`
to read `healthy` before reporting Open WebUI as running, so the dashboard is
not offered while it is still starting.

### Old note — Open WebUI container crashes on its own — exit 255
**Measured 2026-08-27** by running the app's exact command path in the distro.
Everything the app does works:

| Step | Result |
|---|---|
| `_ensureDockerReady` (apt-get docker.io + wait loop) | docker READY |
| `docker pull` + `docker run` | exit 0 |
| `statusCheck` while up | `running` |
| `existsCheck` | `exists` |
| port 8083 | listening (v4 + v6) |
| `statusCheck` after the crash | `stopped` — correct |

But the container itself exits **255** about 40s after start, every time
(`OOMKilled=false`, 3.1 GiB free, nothing in dmesg). Logs run through all the
alembic migrations, print the CORS warning, then stop with no error. A
`docker start` brings it back to "Up (health: starting)" and it dies again.
Nothing ever answers on 8083, inside the distro or from Windows.

So the app's Docker path is verified end to end; **Open WebUI is failing on its
own** in this environment. Its dashboard therefore could not be verified — it
uses the static port rather than a command, so it should work once the
container stays up. Worth trying a pinned older image tag.

### Hermes Agent installer hangs — app handles it correctly
Verified through the UI 2026-08-27: after the 5-minute timeout the card shows
"Fehler", the full `TimeoutException … Command timed out after 300s` detail,
and an enabled **Wiederholen** button. So the failure path is right; the
installer itself is the problem.


`curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive`
runs past 10 minutes and never returns — reproduced manually in the distro, so
it is not our timeout. The endpoint is live (HTTP 200). Either the installer
wants a TTY despite `--non-interactive`, or it waits on something. Decide
whether to raise the 5-minute timeout, stream progress, or drop Hermes from the
tool list until upstream is fixed.

**WSL may still be wedged from the hung install — `wsl --shutdown` clears it.**

### ~~Dashboard~~ — FIXED and verified 2026-08-27
Install, start, stop and **open dashboard** all work end to end with OpenClaw.
Edge opened on "OpenClaw Control". Two causes, both fixed:

1. **Session lifetime.** WSL shuts a distro down when its last session exits,
   taking systemd user services with it. Every action was its own one-shot
   `wsl` call, so the gateway was dead before "open dashboard" ran. Measured:
   listeners 2 (session held) → 2 (25s later, still held) → 0 (20s after the
   holder was killed). `AiWorkspaceService` now holds one
   `wsl -d ai-workspace sleep infinity` session via
   `ExecutionBroker.startPersistent`, released in `dispose()`.
2. **Shell-side URL extraction.** grep patterns, `$(...)` and redirections did
   not survive Dart's Windows argument escaping into wsl.exe, and failed
   silently. The dashboard command now runs bare and the URL is parsed in Dart
   (`_firstServiceUrl`), preferring a loopback address so documentation links
   are not opened instead.

Also fixed on the way: `gateway install --force` prevented the gateway from
binding; the status check tested process existence rather than the port; and
`canLaunchUrl` was gating the launch (every other launch site in the app calls
`launchUrl` directly).

### Superseded — dashboard cannot work with one-shot `wsl` calls
**Measured 2026-08-27.** The OpenClaw gateway does not survive the WSL session
that starts it:

```
A (same session, after restart): 2 listeners on 18789
B (new session, 20s later):      0 listeners
```

`loginctl enable-linger root` does not change this. Every app action is a
separate one-shot `wsl -d ai-workspace ...` invocation, so the gateway is
already dead by the time "Dashboard öffnen" runs — which is why it still fails
even with a correct URL, a correct wait, and a truthful status check.

The status check is now port-based and honest *at the moment it runs*, but the
card can still read "läuft" seconds after the gateway has gone.

Fixing this needs one of:
- a WSL session held open for the app's lifetime (large change), or
- a genuinely detached daemon — systemd **system** service, or a correctly
  `setsid`/`nohup`-ed `node .../openclaw/dist/index.js gateway`. A quick
  `setsid` attempt through PowerShell did not produce a surviving process, but
  that test was inconclusive (no log file was created); it is worth retrying
  from a script file rather than an inline command.

Hermes already uses the `setsid` shape, so it may not have this problem — it
could not be tested because its installer hangs.

### Unexplained: `bash: -c: line 2: syntax error near unexpected token '2'`
Hit when a start command containing `$(seq 1 20)` and subshell parentheses was
added; removing both made it go away. But identical constructs elsewhere in the
same file (`_s=$(...)` in `refreshStatus`, `(apt-get ...)` in
`_ensureDockerReady`, `url=$(...)` in the dashboard command) work fine, so
"parentheses are mangled" is **not** a sufficient explanation. The same error
appeared in a user report before those constructs existed. Root cause still
unknown — worth isolating before trusting any long WSL command string.

### Superseded: dashboard reports success on a process that is not serving
Click-through done with OpenClaw on 2026-08-27: **install, start and stop all
work.** Dashboard does not.

The status check is `pgrep -f '[o]penclaw'`, which only proves *a process
exists*. The gateway process was live (`/usr/bin/node .../openclaw/dist/index.js
gateway --port 18789`, PID 398) while `openclaw dashboard` still answered
"Gateway is not running." and nothing was listening on 18789 per `ss -ltnp`.
So the card says "läuft" while the service is not usable, and the dashboard
then fails with a generic message.

`openclaw dashboard` does print `Dashboard URL: http://127.0.0.1:18789/` when
the gateway is genuinely healthy, so the app's grep is fine — the status is the
problem.

Fix: make `statusCheck` reflect service health, not process existence — probe
the port or use `openclaw gateway status`. Same reasoning applies to Hermes
(`pgrep -f '[h]ermes.*gateway'`).

Worth noting the gateway is a systemd **user** service; that is fragile inside
WSL, which may be why it never binds.

### Failed install loses its error text
After an install fails the watcher re-probes and overwrites `error` with
`notInstalled`, clearing `errorMessage`. Accurate, but the user never gets to
read why it failed. Keep the message until the next user action.

### Stale `installPath` after a tool disappears
A card can read "Nicht installiert" while still showing
`Installed: cmd://openclaw` underneath. `refreshStatus()` should clear
`installPath` when it resolves to `notInstalled`.

---

## Before the next commit / release

### Remove the Pro test hack — blocking
`lib/api/license_manager.dart:64` has `return true;` at the top of
`_detectStoreInstall()`. **It grants Pro to every install.** Still needed to
exercise the Pro-gated AI Workspace, so it stays until testing is done — but it
must not be committed.

It is the sole cause of the only 4 failing tests (294 pass):
- `license_manager_test.dart` — "no package identity means free plan",
  "a leftover legacy grant no longer unlocks Pro", "a GitHub build is never asked"
- `ai_service_test.dart` — "throws pro-required when not Pro"

### Commit the working tree
`lib/api/ai_workspace/service.dart`, `lib/screens/ai_workspace_screen.dart`,
`lib/screens/create_screen.dart`, `lib/nav/router.dart`, `lib/nav/panelist.dart`,
`lib/components/list.dart`, `lib/components/navbar.dart`, `lib/i18n/*.json`,
`pubspec.yaml`, `assets/logo*.png`, `windows/runner/resources/app_icon.ico`,
plus `TODO.md`.

---

## Store

### Keywords will not save in Partner Center
Seven controlled trials; the field silently reverts with no error and no failed
request. Ruled out: the 21-word cap, the "Windows" trademark, emptying the
field, one-change-per-save. Current value:
`wsl, manager, gui, linux, wsl2, docker, virtual disk compact`
Next step: try one swap by hand; if it reverts for you too, raise it with
Partner Center support.

### Refresh "What's new in this version"
Still the old notes ("Fixed window not closing…"). Should describe the bug-fix
release before submitting.

### Submission 71 is still a draft
Description, short description, 11 features, 8 screenshots and all 5 logo slots
are in place. Never submitted.

---

## Housekeeping

### `lib/components/navbar.dart` is dead code
Nothing imports it. It also carries a stale `supportedLocales` list including
`zh_HK`, which has no translation file — exactly the pattern that blanks the
whole app. Delete it or fix the list.

### Screenshot capture is misaligned
The scratchpad helpers capture ~8px outside the window on every side. The Store
screenshots were cropped by hand this time; fix at the source if regenerated.

### Build pins to re-check before release
- Flutter `3.41.6` in both workflows (`re_editor` breaks on newer). Local
  toolchain matches.
- `releaser.yml` pins `CodeDependencies.iss` to commit `7ab4aac4…` because
  upstream edited `master` and broke the checksum.

---

## Decisions open

### Mac version with Apple Virtualization
Microsoft Store and Mac App Store share no entitlements, so a cross-platform
user pays twice. Recommendation: accept that rather than build a licence
server, which would undo the no-account, no-key design.
