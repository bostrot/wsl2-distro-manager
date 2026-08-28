# Phase 08: Fix the UI/UX Findings and Verify the Whole Backlog

This final phase works the ordered fix list in `doc/audit/ui-ux/index.md` from the top, re-screenshots the affected surfaces to prove each fix, and then re-verifies the whole playbook: tests green, analyzer clean, no orphaned `wsl.exe` processes, no Pro hack in the tree, and `TODO.md` honestly reflecting what is done and what remains. Fix in batches by area so each commit is reviewable, and treat the audit index — not this document — as the authoritative scope.

Apply the Phase 01 repo conventions throughout: CRLF-safe edits, format only touched files, append i18n keys without sorting, never add a locale without its file, and use `secondaryTextColor(context)` / `disabledTextColor(context)` instead of hardcoded greys. Search `lib/components/` for an existing widget before building a new one.

## Tasks

- [ ] Fix every **blocker** and **major** finding from `doc/audit/ui-ux/index.md`, working top-down and grouping edits by file so each area lands as one coherent change. Update the finding's row in the audit index with the fix location (`file:line`) as you go.

  **In progress — 21 of 214 findings closed (5 blockers, 13 majors, 3 nits).** Running
  tally lives in the [Progress](../../../doc/audit/ui-ux/index.md#progress) table in the
  audit index; each work item's own table carries a `Fixed in` column, `--` = still open.
  Ordered by the index's own sequencing note (FIX-03 is groundwork for FIX-02 and FIX-05,
  so it went first), not by work-item number.

  - **FIX-03 — one honest notification surface: complete (9/9).** `Notify.message` takes
    an `InfoBarSeverity`; `statusBuilder` no longer overrides fluent's per-severity
    decoration with one flat colour; an empty bar renders `SizedBox.shrink` instead of an
    invisible 126x62 hit target; the close X is withheld while an operation runs; the bar
    is a `Column` child rather than an overlay, so it can no longer cover Create/Cancel;
    messages expire after 8s and are dropped on navigation. `DONE:`/`ERROR:`/`WARNING:`
    prefixes removed from six keys across all nine locales.
  - **FIX-02 — report what actually happened: 5/10.** Closed: IA-13 (`WSLApi.start` is
    now `Future<void>` and awaited — the `Future.delayed(d, Notify.message(...))` at the
    call site was calling the function immediately, so the toast fired before the spawn
    and the catch was unreachable), CI-12, CI-17, IA-12, PS-17. Still open: CI-36, ST-53,
    ST-45, PS-19, PS-32 — all per-screen work in `qa_dialog.dart`,
    `settings_screen.dart` and `ai_workspace_screen.dart`.

  - **FIX-01 — stop discarding what the user typed: complete (7/7).** A new
    `UnsavedChangesGuard` (`lib/components/unsaved_changes.dart`) lets a dirty screen
    register an exit guard; every nav-pane item, the app-bar back button, the window X
    and the two in-screen buttons that navigated on their own now ask before building
    the next screen. Settings compares a draft snapshot against the last saved one
    rather than trusting a dozen controls to set a flag, which also drives the new
    "Unsaved changes" marker and Discard button. The save-on-`dispose()` that was meant
    to commit on exit and observably never fired is gone. Language is in the draft and
    previews live (`localeResolutionCallback` now prefers `AppTheme.locale` over the
    stored preference, or the stored value would win on the rebuild the preview
    triggers); Save confirms in place instead of teleporting to Home; the free MCP
    toggle is disabled with its hint dimmed instead of replacing the screen; the AI chat
    panel says why Send did nothing *in* the panel and keeps the typed question; and the
    per-distro dialog buffers `wsl.conf` edits so Cancel cancels and Save is the only
    thing that touches the distro. ST-27 is answered by warning up front — there is no
    way to read `/etc/wsl.conf` without `wsl.exe` booting the distro — so a stopped
    distro gets a notice and a "Start it and read the settings" button.

  **Next up:** FIX-05 (error text a user can act on), then FIX-06/FIX-07 (keyboard and
  accessible names), then the five open FIX-02 items. Verification for this slice:
  `flutter analyze` clean (two warnings, both pre-existing and untouched),
  `flutter test` 732 passing (was 721), `dart run scripts/check_translations.dart`
  exit 0.

- [ ] Fix the text-quality findings across the app:
  - Replace every user-facing message containing a raw exception, a bare colon, a stack trace or an unactionable shell command with a sentence explaining what failed and what to do next, keeping the technical detail available in an expandable/secondary position
  - Apply consistent capitalisation and button-label style across screens and dialogs
  - Update all nine locale files by appending the new keys (never sorting) with real translations, then run the translation check script in `scripts/` and `flutter test test/locales_test.dart`

- [ ] Fix the theme and layout findings:
  - Replace every hardcoded `Colors.grey` (and any other non-theme colour flagged) with the helpers from `lib/components/helpers.dart`
  - Fix truncation and overflow at the narrow window width and in the longest locales (typically de and hu)
  - Fix spacing, alignment and button-order inconsistencies so equivalent controls sit in the same place on every screen

- [ ] Fix the accessibility findings:
  - Wrap every flagged icon-only button and its `Tooltip` in `MergeSemantics` so the label reaches the button's semantics node
  - Ensure every `PaneItem.title` is a real `Text` widget
  - Fix tab order and keyboard reachability so a keyboard-only user can complete create, start, stop and delete
  - Add semantic labels to any control announced as a bare "button"

- [ ] Fix the remaining **nit** findings, or explicitly defer them:
  - Work them in a single pass grouped by file
  - For any nit deliberately not fixed, mark it deferred in the audit index with a one-line reason — do not silently drop findings

- [ ] Add regression tests for the fixes that are testable without a display:
  - Widget tests for empty states, error-state rendering and disabled-control conditions
  - A test asserting no user-facing string in `lib/i18n/en.json` contains an exception-shaped fragment (`Exception:`, `#0 `, `TimeoutException`)
  - Extend `test/helpers_test.dart` if new colour/formatting helpers were introduced

- [ ] Re-run the click-through and prove the fixes visually:
  - Launch with `.maestro/tools/launch.ps1`, revisit every screen and dialog changed in this phase, and capture `.maestro/screenshots/phase-08/` shots at the same window sizes as Phase 07
  - Diff them against the Phase 07 captures and confirm each fixed finding is visibly resolved
  - Record the before/after pairs in `doc/audit/ui-ux/index.md`

- [ ] Run the full verification sweep and fix anything it surfaces:
  - `flutter analyze` — no errors
  - `flutter test` — all tests passing; record the final count
  - `flutter build windows --release` — succeeds on the pinned Flutter 3.41.6 toolchain
  - Leave the app running for ~5 minutes on the distro list and confirm `(Get-Process wsl).Count` is stable (the Phase 01 broker fix still holds)
  - `grep -n "return true;" lib/api/license_manager.dart` — confirm no unconditional Pro grant
  - `git status --short` — confirm no stray tooling files, screenshots or scratch output are staged

- [ ] Rewrite `TODO.md` to match reality:
  - Move every item completed across Phases 01–08 into a dated done section with a one-line statement of how it was verified
  - Keep only genuinely open items in "Now", including anything deferred from the audits, with a pointer to the relevant `doc/audit/` file
  - Commit the UI fixes, the tests and the updated `TODO.md` on `beta`, then summarise for the user what changed, what still needs a manual step (the `images.json` CDN push), and what was deliberately deferred.
