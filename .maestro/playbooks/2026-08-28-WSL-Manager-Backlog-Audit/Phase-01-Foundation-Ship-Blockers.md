# Phase 01: Foundation, Ship-Blockers and a Verified Running Build

This phase clears the two ship-blockers recorded in `TODO.md` — the `ExecutionBroker` process leak that produced 842 orphaned `wsl.exe` processes on 2026-08-27, and the `return true;` Pro hack in `license_manager.dart` that grants Pro to every install and is the sole cause of the 4 failing tests — then cleans the working tree and builds the UI-automation tooling every later phase depends on. It ends with the app running, a screenshot on disk, `flutter analyze` clean and the full test suite green: tangible proof the foundation is solid before any feature work starts.

## Repo Conventions (read before editing any Dart file)

These are measured facts from `SESSION-HANDOFF.md`, not guesses. Violating them silently breaks the app.

- Most `.dart` files use **CRLF**. Regex/perl one-liners matching `\n` fail silently. Prefer the Edit/Write tools; if scripting, detect CRLF and convert the replacement text.
- `dart format` is **not** clean across the repo. Format only files you touched, then check `git diff --stat`.
- The i18n JSON files are **not** alphabetically sorted. Append keys, never sort.
- **Never add a locale to `supportedLocalesList` without a matching `lib/i18n/<locale>.json`** — a missing file throws in `LocalJsonLocalization` and renders the entire app blank.
- Use `secondaryTextColor(context)` / `disabledTextColor(context)` from `lib/components/helpers.dart`; hardcoded `Colors.grey` is invisible on the dark theme.
- Before writing new code, search for the existing pattern (`grep -rn` over `lib/`) and reuse it. This repo already has helpers for shells, paths, VHDX resolution, notifications and dialogs.

## Tasks

- [x] Clean the working tree and extend `.gitignore`:
  - Inspect the stray `-o` file at the repo root (`ls -la -- -o`, then `head -c 400 -- ./-o`); if it is redirection garbage, delete it, otherwise leave it and note why in `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/tree-cleanup.md`
  - Append a `# Local tooling / agent configs` block to `.gitignore` covering: `/-o`, `.opencode/`, `.slim/`, `opencode.jsonc`, `opencode-mem.jsonc`, `qwencode.json`, `roo-code-settings.json`, `vscode-settings.json`, `semble-search-agent.md`
  - Append a `# Maestro` block covering `.maestro/screenshots/` and `.maestro/playbooks/**/Working/` (playbook `Phase-*.md` documents stay tracked)
  - Confirm with `git status --short` that only intended files remain untracked

  > **Done 2026-08-28.** `./-o` was 10,485,860 bytes of pure NUL (every byte stripped by `tr`, leaving 0), untracked with no history — redirection garbage, deleted. Both `.gitignore` blocks appended with CRLF endings to match the file. All 11 patterns verified with `git check-ignore -v`; the control probe `Phase-01-*.md` correctly does not match, so playbook documents stay trackable while `Working/` and `screenshots/` are ignored. Remaining untracked: `.maestro/` (only the eight `Phase-0*.md` docs), `SESSION-HANDOFF.md`, `TODO.md`, `lib/screens/create_screen.dart`. Details in `Working/tree-cleanup.md`.

- [x] Build the durable UI-automation toolkit in `.maestro/tools/` (PowerShell, window-relative coordinates). The scratchpad versions from the previous session are gone and had two known bugs — fix both at the source:
  - `focus.ps1` — bring the app window to the foreground; loop minimising the stealing foreground window until `GetForegroundWindow()` equals the app handle
  - `shot.ps1` — capture the app window to a PNG. The old helper captured ~8px outside the window on every side; use `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` instead of `GetWindowRect` so the capture is exact
  - `resize.ps1` — call `MoveWindow` directly, **not** `ShowWindow(SW_RESTORE)`, which races the app's own startup geometry restore
  - `click.ps1`, `key.ps1`, `type.ps1`, `scroll.ps1` — window-relative input helpers
  - `launch.ps1` — kill any running instance, start the app, wait ~10s for geometry restore, focus it, and print the window handle
  - `.maestro/tools/README.md` documenting each helper's parameters and the two traps above

  > **Done 2026-08-28.** Nine files in `.maestro/tools/`: `_common.ps1` (shared P/Invoke surface, window resolution, DWM bounds, coordinate conversion — every helper dot-sources it, nothing is duplicated), the seven helpers, and `README.md`.
  >
  > Both named bugs fixed and demonstrated on the real app (existing Release build): `shot.ps1` now uses `DWMWA_EXTENDED_FRAME_BOUNDS` and captures **1280x800 exactly** where the `GetWindowRect` path captures 1294x807 with visible desktop on all four sides — the invisible resize border measures 7px left/right/bottom on this machine. `-Raw` was kept so the bug stays reproducible. `resize.ps1` calls `MoveWindow` only, compensates the same border so `-Width`/`-Height` are the *visible* size, and `launch.ps1` waits 10s after the window appears before touching geometry.
  >
  > Three further bugs found while verifying: (1) `ctrl+a`/`delete` did nothing in Flutter text fields — the embedder maps physical keys from the lParam **scan code**, so `SendInput` with `wScan = 0` is silently dropped; fixed via `MapVirtualKey`. (2) `AttachThreadInput` to a modal thread hangs `SetForegroundWindow` forever (a stray "Open with" dialog wedged `focus.ps1` for 2min); `ForceForeground` now probes with `SendMessageTimeout(WM_NULL, SMTO_ABORTIFHUNG)` first. (3) The scripts are pure ASCII — PS 5.1 reads BOM-less files as ANSI and an em dash decodes into a string-terminating smart quote.
  >
  > Every helper verified against the live app: launch/focus/resize/click/type/key/scroll all pass. Layout+escaping regression: `yz@-Test+^%~(1){2}[3]/\` typed into the instance-name field and all 23 characters read back off a screenshot (German layout would swap `y`/`z`; SendKeys would eat `+^%~(){}`). Details and evidence in `Working/ui-toolkit.md`.
  >
  > Note: `launch.ps1 -ForcePro` passes `--dart-define=WSLM_FORCE_PRO=true`, but the gate itself is added by the licence task below; the README says so explicitly rather than claiming it works today.

- [x] Fix the `ExecutionBroker` timeout process leak in `lib/api/execution/broker.dart` (~lines 110–124). `Process.run` returns no handle, so the `onTimeout` throw abandons the child forever, and `list.dart` re-polls every 5 seconds:
  - Route the non-streaming `run()` path through `_shell.start` (the streaming path at ~line 197 already does this) so a killable `Process` handle exists
  - Collect stdout/stderr from the streams, preserving the existing UTF-16LE raw-bytes handling for WSL commands (`isWsl ? null : systemEncoding` semantics must survive)
  - On timeout, `kill()` the process (escalate to `ProcessSignal.sigkill` if it does not exit promptly) **before** throwing the `TimeoutException`, keeping the existing message text
  - Leave the audit-log bookkeeping, policy check and `ExecutionResult` shape unchanged so callers need no edits

  > **Done 2026-08-28.** `run()` now goes through `_shell.start`. Output is drained into two `List<int>` buffers by explicit subscriptions whose `onDone`/`onError` feed a `Completer` each (`asFuture()` would deadlock on an already-finished stream), and the completion future awaits `process.exitCode` *then* both drains — the same ordering `Process.run` uses.
  >
  > The encoding split survives as a local `decode()` closure: WSL bytes go to `decodeWslOutput` untouched (UTF-16LE, null bytes stripped), everything else goes through a new `_decodeSystem()` that runs `systemEncoding.decode` and falls back to a lenient UTF-8 decode on `FormatException` — expressing exactly what `stdoutEncoding: isWsl ? null : systemEncoding` used to.
  >
  > The timeout `catch` is now a general `catch (e)`, not just `on TimeoutException`: a stream error would otherwise leak the child too. It calls `_terminate(process)` — `kill()`, then `await exitCode` capped at 2s, escalating to `ProcessSignal.sigkill` — then cancels both subscriptions, then rethrows the `TimeoutException` with the original message text. Policy check, audit bookkeeping and `ExecutionResult` are untouched; no caller needed an edit.
  >
  > Verified with a scratch test (since the regression tests belong to the task below): a 30s child against a 50ms timeout yields `exitCode -1`, stderr containing `timed out after 0s`, and `killCount == 1`. Decoding checked both ways — `h\0e\0l\0l\0o\0` through the `wsl` path reads back as `hello`, plain text through the `echo` path is unchanged.
  >
  > **Suite kept green, which forced part of the next task early.** Both `TestShell.start` mocks threw `UnsupportedError`, so every `run()` test would have failed. `test/mocks.dart`'s existing `MockProcess` was extended in place rather than adding a third process fake — it now takes an optional `delay` (the child stays alive that long; `kill()` cuts it short) and records `killCount` / `lastKillSignal`. Both test files' `TestShell.start` return one and honour `throwOnRun`. Two `runStream` tests asserted on `start()` being unimplemented (`StdOutChunk events not emitted when start fails`, `ExecutionExited not emitted when start fails`); they now set `throwOnRun = true` so they test what their names claim.
  >
  > `flutter analyze` on the changed files: clean (the one `override_on_non_overriding_member` warning at `test/mocks.dart:331` is pre-existing, in `MockChunkedDownloader`). `flutter test`: **294 passing, 4 failing** — the same four Pro-hack failures recorded in `TODO.md` (`license_manager_test.dart` × 3, `ai_service_test.dart` × 1), no new breakage. Full log in `Working/full-test-run-task03.txt`.
  >
  > Not formatted: `dart format` would rewrap ~12 pre-existing lines in `broker.dart` and ~25 in the test file that this change never touched. New code was hand-checked to be format-stable, so the formatting pass at the end of this phase produces no surprises.

- [x] Update `test/execution_broker_test.dart` for the new execution path:
  - ~~The existing mocks stub `Shell.run`; move them to `Shell.start` with a fake `Process` exposing stdout/stderr streams, `exitCode` and `kill()`~~ — **already done** by the broker task above (see its note); the mock lives in `test/mocks.dart` as `MockProcess` and is used by both `execution_broker_test.dart` and `ai_workspace_service_test.dart`
  - Add a regression test proving a command that exceeds its timeout results in `kill()` being called on the child exactly once and a `TimeoutException` propagating to the caller
  - Add a test that stdout/stderr are still assembled correctly for both the WSL (raw bytes) and non-WSL (`systemEncoding`) branches

  > **Done 2026-08-28.** Nine tests added in two new groups; `execution_broker_test.dart` goes 30 → 39, all green.
  >
  > **`ExecutionBroker timeout reaping`** — a 30s child against a 50ms timeout asserts `killCount == 1` and `lastKillSignal == sigterm` (SIGKILL escalation only fires when the child ignores the first signal, so a second kill here would be a bug, not thoroughness). A companion test pins where the `TimeoutException` surfaces: `run()` reports failures on the result rather than throwing, so it arrives as `result.error` with the message `Command timed out after 0s: wsl --list --verbose`, mirrored into `result.stderr` and `auditLog.last.errorMessage`. A third test guards the other direction — a command that finishes inside its timeout must have `killCount == 0`.
  >
  > **`ExecutionBroker output decoding`** — six tests over the `isWsl ? bytes : _decodeSystem(bytes)` split. WSL stdout *and* stderr decode `h\0e\0l\0l\0o\0` to `hello` (`utf8.encode` maps `'\u0000'` to one 0x00 byte, so the Dart string literal *is* the byte sequence wsl.exe writes); a full `C:\Windows\System32\wsl.exe` path takes the same branch; UTF-8 `café` bytes on a non-WSL command decode to whatever `systemEncoding` says rather than to UTF-8 — asserted against `systemEncoding.decode` itself so the test still holds on a UTF-8-codepage host, though on this machine the two genuinely differ (`cafÃ©` vs `café`), so the split is really pinned. Plus ASCII passthrough and empty-output cases.
  >
  > **Chunk assembly.** `MockProcess` emitted each stream as one `Stream.value`, which cannot show whether `run()` buffers bytes before decoding. It now takes optional `stdoutChunks`/`stderrChunks` (`List<List<int>>`, one stream event per entry) that override the string form; `TestShell` forwards them. A test splits the two UTF-8 bytes of `é` across two events and expects `é!` — per-chunk decoding would yield replacement characters. No new fake was added; `MockProcess` was extended, as it was for the broker task.
  >
  > **Mutation-checked, so the tests demonstrably bite.** Replacing `decodeWslOutput(isWsl ? bytes : _decodeSystem(bytes))` with `decodeWslOutput(bytes)` and deleting the `await _terminate(process)` call fails exactly two tests and no others (`Expected: <1> Actual: <0>` and `Expected: 'cafÃ©' Actual: 'café'`). `broker.dart` was restored byte-for-byte afterwards — `git status` confirms it is untouched.
  >
  > `flutter analyze` on both files: clean (the `override_on_non_overriding_member` warning now at `test/mocks.dart:339` is the same pre-existing one in `MockChunkedDownloader`, shifted by 8 lines). Full suite: **303 passing, 4 failing** — up from 294 passing, with the same four Pro-hack failures the next task removes (`license_manager_test.dart` × 3, `ai_service_test.dart` × 1). Log in `Working/full-test-run-task04.txt`.
  >
  > Not formatted, same reasoning as the broker task: `dart format` rewraps eight pre-existing lines in the `audit log accumulates entries` / `clearAuditLog` / `runStream` blocks that this change never touched. One new test name was shortened so that the formatter leaves every added line alone — verified by formatting in place and confirming the only changed ranges are the pre-existing ones. `mocks.dart` is already format-clean.

- [ ] Remove the Pro test hack and replace it with a safe developer override:
  - Delete the unconditional `return true;` at the top of `_detectStoreInstall()` in `lib/api/license_manager.dart:64`
  - Keep the existing `storeInstallCheckOverride` hook untouched (tests depend on it)
  - Add a debug-only gate immediately after it: when `kDebugMode` is true **and** `const bool.fromEnvironment('WSLM_FORCE_PRO')` is true, return `true`. In a release build and with no dart-define the behaviour is unchanged, so this can be committed safely
  - Document the flag in `.maestro/tools/README.md`: Pro click-throughs in later phases run `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true`

- [ ] Run `flutter analyze` and `flutter test`, then fix every failure:
  - The 4 previously failing tests (`license_manager_test.dart` × 3, `ai_service_test.dart` × 1) must now pass
  - Target: 298+ tests passing, analyzer reporting no errors
  - Record the before/after counts in `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/phase-01-results.md`

- [ ] Prove the leak fix on the real app:
  - Launch with `.maestro/tools/launch.ps1` (release-flavoured `flutter run -d windows` is fine)
  - Record `(Get-Process wsl -ErrorAction SilentlyContinue).Count` immediately after launch, then again after leaving the distro list polling for ~3 minutes; the count must not grow
  - Capture `.maestro/screenshots/phase-01/home.png` with `shot.ps1` and confirm the window content is flush to the image edges (the 8px-offset bug is gone)
  - Append both observations to `Working/phase-01-results.md`

- [ ] Format only the files you touched (`dart format lib/api/execution/broker.dart lib/api/license_manager.dart test/execution_broker_test.dart`), verify `git diff --stat` shows no unrelated churn, then stage and commit everything on the `beta` branch with a message describing the broker fix, the licence-hack removal and the tree cleanup. Before committing, `git diff --cached lib/api/license_manager.dart` and confirm no unconditional `return true;` is present.
