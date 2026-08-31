# TODO

Working list for WSL Distro Manager. Longer background lives in the audit
reports under `doc/audit/` and the playbook under
`.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/`.

---

## Now

### Push `images.json` to the CDN — the one manual step left from the audit
The repo copy of `images.json` is **not** the runtime source in release: the
app fetches `https://n8n.aachen.dev/webhook/cdn/images.json` first and falls
back to the bundled asset only when that request fails. Measured 2026-08-31:
the endpoint currently answers **HTTP 200 with an empty body**, so release
users are living on their installer's bundled copy anyway — one more reason
the upload matters. The exact payload and steps:
`.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/cdn-upload.md`.

Debug builds now skip the CDN entirely and read the repo's own `images.json`
(`App.preferBundledCatalogue`, on under `kDebugMode`, off under
`flutter test`), so a catalogue edit is testable in `flutter run` before the
push — verified live 2026-08-31 in a `WSLM_FORCE_PRO` debug run: the create
screen's suggestion list served the repo's 19 entries (Ubuntu 26.04 first).

### Register the app for "Sign in with Claude"
The AI chat can now run on a Claude subscription instead of an API key
(Settings → AI, provider "Claude subscription"). The OAuth/PKCE flow is
implemented and tested, but it needs a client ID from Anthropic's
Sign in with Claude registration (Anthropic Console) before the button works
for users — bake it in with `--dart-define=WSLM_CLAUDE_CLIENT_ID=...` or set
it in the settings field. Do not ship another product's client ID.

### Wire remote WSL onto `RemoteShell` (optional cleanup)
The `RemoteShell` class exists but is not instantiated in production —
`wsl.dart` decides local-vs-remote itself and builds `ssh … wsl …` inline, and
`mount_service.dart` calls `shell.run` directly rather than the broker.
`doc/remote-execution-architecture.md` has been corrected to say so (2026-08),
so nothing is *wrong* now; routing those call sites through `RemoteShell` +
the broker would be a consistency cleanup, not a fix. Needs a real remote host
to verify.

### Hermes install tail noise (upstream)
`uv sync --locked` errors on a stale `uv.lock` — non-fatal, but it dominates
any failure tail shown on the card.

### Integration tests cannot run on this host
`flutter test integration_test/` builds the app and then fails with "Unable to
start the app on the device" / "The log reader stopped unexpectedly" — an
environment problem, not a code one, reproduced identically across every
Phase 08 slice. Worth retrying after the next Flutter upgrade; until then the
e2e suite is only exercised in CI or on another machine.

---

## Store

### Keywords will not save in Partner Center
Seven controlled trials; the field silently reverts with no error and no
failed request. Ruled out: the 21-word cap, the "Windows" trademark, emptying
the field, one-change-per-save. Current value:
`wsl, manager, gui, linux, wsl2, docker, virtual disk compact`
Next step: try one swap by hand; if it reverts for you too, raise it with
Partner Center support.

### Refresh "What's new in this version"
Still the old notes ("Fixed window not closing…"). Should describe this
release — the UI/UX audit alone closed 214 findings — before submitting.

### Submission 71 is still a draft
Description, short description, 11 features, 8 screenshots and all 5 logo
slots are in place. Never submitted.

---

## Build pins to re-check before release
- Flutter `3.41.6` in both workflows (`re_editor` breaks on newer). Local
  toolchain matches.
- `releaser.yml` pins `CodeDependencies.iss` to commit `7ab4aac4…` because
  upstream edited `master` and broke the checksum.

---

## Decisions open

### Remove or merge Templates into Distro packages
Templates (app-internal snapshot tars) and Distro packages (official `.wsl`
files with `wsl-distribution.conf`) solve the same problem; packages are the
portable superset. The Templates screen now carries a deprecation banner
pointing at Distro packages (2026-08-31). Open: pick removal or merge — a
merge would mean a "convert template to package" path so existing template
files are not orphaned — and drop the Home-row archive button along with it.


### Mac version with Apple Virtualization
Microsoft Store and Mac App Store share no entitlements, so a cross-platform
user pays twice. Recommendation: accept that rather than build a licence
server, which would undo the no-account, no-key design. Note: no `macos/`
scaffolding exists — this would be a from-scratch, multi-week effort.

---

## Done — the 2026-08 backlog audit (Phases 01–08)

Each phase's full record lives in its playbook file; verification is quoted
from there.

### Follow-ups closed 2026-08-31
- **Remote WSL argv quoting** — `_buildRemoteArgs(quoteCommand: true)` now
  POSIX single-quotes each remote-command token so the remote login shell
  keeps it whole; a `bash -c 'a | b'` no longer loses everything after the
  first space over SSH. The exec paths (`_runWsl`, `_brokeredWsl`,
  `_startWsl`) opt in; the interactive terminal launches stay raw. Verified:
  `wsl_test.dart` "a remote command with spaces and metacharacters is quoted
  whole".
- **Keep-alive survives a hard kill** — `ProcessReaper` puts every child
  started through `ProcessShell.start` into a Windows job object with
  `KILL_ON_JOB_CLOSE`, so a force-kill of the app (Task Manager,
  `Stop-Process -Force`) takes the `wsl … sleep infinity` keep-alive and any
  streaming exec down with it. Best-effort and no-op on failure. Verified:
  `process_reaper_test.dart` confirms an adopted child is actually placed in a
  job (`IsProcessInJob`), and never throws on a bad pid.

### Phase 01 — foundation & ship blockers (2026-08-28)
- **ExecutionBroker kills timed-out children** instead of leaking `wsl.exe`
  (measured 842 orphans before the fix). Verified: leak watch over the 5s
  poll held the process count flat.
- **The unconditional Pro grant is gone** from `license_manager.dart`;
  Pro-gated click-throughs use `--dart-define=WSLM_FORCE_PRO=true`, debug-only.
  Verified: the 4 licence tests that documented the hack pass.
- PowerShell UI-automation toolkit added under `.maestro/tools/`.

### Phase 02 — AI workspace correctness (2026-08-28)
- Docker readiness, install-survives-navigation, retry-from-error, shell
  quoting, sticky failure messages, installPath reset. Verified live against
  the real `ai-workspace` distro and by the service/screen test suites.

### Phase 03 — Hermes/OpenClaw lifecycle (2026-08-28)
- Hermes driven through `serve` (not the messaging gateway), installs
  budgeted by silence (measured 482s cold with 306s of quiet), `--skip-setup`
  for the TTY wizard, port-based status, session keep-alive, dashboard URL
  handling. Verified end to end: install exit 0 in 244s unattended, 9119
  answers HTTP 200 from Windows, stop frees the port.

### Phase 04 — WSL docs audit (2026-08-28)
- The documented `.wslconfig` / `wsl.conf` / CLI surface inventoried, diffed
  against the app, verified against a running WSL 2.6.3, and ranked into the
  Phase 05 list.

### Phase 05 — WSL feature gaps (2026-08-28)
- New `.wslconfig` engine (comment-preserving round trips), `wsl.conf` and
  `wsl-distribution.conf` editors, `--manage` surfaces, custom-distro
  packaging, serialized config writes (measured live: concurrent writes had
  silently dropped keys). Verified: `wsl_test.dart`'s round-trip suites and a
  live runtime pass, both recorded in the playbook.

### Phase 06 — rootfs catalogue (2026-08-28)
- `images.json` re-sourced to official vendor infrastructure, every URL
  verified mechanically, all 19 entries install-tested in the app. Verified:
  the catalogue test suite plus the recorded install runs. **The CDN push is
  the one step still open — see "Now".**

### Phase 07 — click-through UI audit (2026-08-28)
- Every screen, dialog and state walked at 1400x860 and 900x860, light and
  dark, all nine locales: **214 findings** (14 blockers, 107 majors, 93 nits),
  each with `file:line` and a screenshot or measurement, consolidated into 20
  ordered work items in `doc/audit/ui-ux/index.md`.

### Phase 08 — fix the findings (2026-08-28 – 2026-08-30)
- **All 214 findings closed, none deferred**, across all 20 work items —
  unsaved-work guards, honest error reporting, one notification surface,
  cancellable long operations, keyboard operability, accessible names,
  destructive-action styling and confirmation, one dialog contract, theme
  tokens with AA-measured contrast, localization holes (a whole dialog was
  English in six locales), sentence-case copy, an honest paid surface with a
  price, settings validation, the create form, home-list layout, the
  recommendations/chat panels, and the templates/snippets/mount polish pass.
- Verified: `flutter analyze` clean (two pre-existing warnings, untouched),
  `flutter test` 828 passing, `dart run scripts/check_translations.dart`
  exit 0, `flutter build windows --release` succeeds, no `return true;` Pro
  grant in `license_manager.dart`, and the running tally per slice in the
  Phase 08 playbook. The per-finding fix locations live in the `Fixed in`
  columns of `doc/audit/ui-ux/index.md`.
