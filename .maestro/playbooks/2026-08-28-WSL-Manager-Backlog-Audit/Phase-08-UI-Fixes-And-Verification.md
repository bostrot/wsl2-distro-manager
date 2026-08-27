# Phase 08: Fix the UI/UX Findings and Verify the Whole Backlog

This final phase works the ordered fix list in `doc/audit/ui-ux/index.md` from the top, re-screenshots the affected surfaces to prove each fix, and then re-verifies the whole playbook: tests green, analyzer clean, no orphaned `wsl.exe` processes, no Pro hack in the tree, and `TODO.md` honestly reflecting what is done and what remains. Fix in batches by area so each commit is reviewable, and treat the audit index — not this document — as the authoritative scope.

Apply the Phase 01 repo conventions throughout: CRLF-safe edits, format only touched files, append i18n keys without sorting, never add a locale without its file, and use `secondaryTextColor(context)` / `disabledTextColor(context)` instead of hardcoded greys. Search `lib/components/` for an existing widget before building a new one.

## Tasks

- [ ] Fix every **blocker** and **major** finding from `doc/audit/ui-ux/index.md`, working top-down and grouping edits by file so each area lands as one coherent change. Update the finding's row in the audit index with the fix location (`file:line`) as you go.

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
