# Phase 08: Fix the UI/UX Findings and Verify the Whole Backlog

This final phase works the ordered fix list in `doc/audit/ui-ux/index.md` from the top, re-screenshots the affected surfaces to prove each fix, and then re-verifies the whole playbook: tests green, analyzer clean, no orphaned `wsl.exe` processes, no Pro hack in the tree, and `TODO.md` honestly reflecting what is done and what remains. Fix in batches by area so each commit is reviewable, and treat the audit index — not this document — as the authoritative scope.

Apply the Phase 01 repo conventions throughout: CRLF-safe edits, format only touched files, append i18n keys without sorting, never add a locale without its file, and use `secondaryTextColor(context)` / `disabledTextColor(context)` instead of hardcoded greys. Search `lib/components/` for an existing widget before building a new one.

## Tasks

- [ ] Fix every **blocker** and **major** finding from `doc/audit/ui-ux/index.md`, working top-down and grouping edits by file so each area lands as one coherent change. Update the finding's row in the audit index with the fix location (`file:line`) as you go.

  **In progress — 87 of 214 findings closed (8 blockers, 52 majors, 27 nits).** Running
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
  - **FIX-02 — report what actually happened: complete (10/10).** The first five
    were IA-13 (`WSLApi.start` is now `Future<void>` and awaited — the
    `Future.delayed(d, Notify.message(...))` at the call site was calling the
    function immediately, so the toast fired before the spawn and the catch was
    unreachable), CI-12, CI-17, IA-12 and PS-17. The last five were per-screen,
    and three of them were one defect written out three times: a primary button
    whose entire response to an empty required field was to do nothing. ST-45's
    `if (…text.isEmpty) return;` sat *inside* the try that had already set
    `_loading`, so Unmount on an empty path flashed a progress bar and changed
    nothing; ST-53's else branch was the comment `// Error`; and the community
    dialog let Download close over an empty selection. All three now name the
    field they are waiting for and clear the message as soon as it stops being
    true. CI-36 is the same class one level up: `download()` caught its own
    failure, posted a three-word toast and returned normally, so the dialog
    popped and ran the *success* callback on a failed download — it now returns
    a `QaDownloadResult`, the dialog stays open with the reason and a
    "Technical details" disclosure, the catalogue's own load failure gained a
    retry that drops the process-lifetime static cache (nothing could reload it
    without restarting the app), and the download reports "Downloading 2 of 4"
    while it runs and confirms when it lands. PS-19 gave the AI Workspace card
    an "Installing" badge: the pill read **Not Installed** in grey directly
    above a live spinner for the whole of a six-minute install, because
    `isChecking` had a badge substitution and `isInstalling` did not. PS-32 was
    `stop()`'s failure path assigning `errorMessage` directly instead of going
    through `_recordActionFailure`, which left `status` on `running` — a red
    error line under a green pill — and left the failure non-sticky, so the
    next background probe erased the only feedback a stop has.
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

  - **FIX-05 — error text a user can act on: complete (12/12).** One new file,
    `lib/api/wsl_errors.dart`, is the root of it: `WslFailure` reads *both* process
    streams, pulls the stable `Wsl/…` code out of localized prose, maps it to a
    translated sentence and keeps the tool's own words in `details`.
    `lib/components/error_view.dart` renders that shape — sentence first,
    "Technical details" folded away underneath — and the mount dialog, the create
    banner, the distro-list error state and the AI Workspace page all use it. The
    blocker (IA-16) was `mount_service.dart` throwing `Exception(result.stderr)`
    over a `wsl --mount` failure that WSL had written to *stdout*, so the dialog
    body was literally the word `Exception:`; the reason and its
    `Wsl/ERROR_PATH_NOT_FOUND` code were in hand and thrown away. The two streams
    are not interchangeable and the fix does not treat them as such: stderr wins
    the text (`wsl --import` paints progress on stdout, and showing that instead
    of the reason is its own bug, guarded by `wsl_test.dart`), stdout is read when
    stderr is silent, and stdout's *code* is taken whenever stderr carries none.
    The disk-in-use hint is now gated on `ERROR_SHARING_VIOLATION` rather than on
    the English phrases "process cannot access" / "being used by another process",
    which could never fire on this German-locale host. 47 new keys landed in all
    nine locales with real translations; `globalconfigurationinfo-text` and
    `diskofflinehint-text` were rewritten to stop naming a command, and the
    Settings note now sits beside a Restart WSL button instead of telling the user
    to open a terminal. IA-20's xterm half is answered by copying rather than
    installing — that terminal lives on the *host*, so the app cannot elevate to a
    package manager; the dialog hands over the command instead.

  - **FIX-06 — keyboard operability: complete (9/9).** One new file,
    `lib/nav/shell_focus.dart`, holds the two pieces that are not per-widget:
    `shouldAdoptKeyboardFocus()` — the test for the state IA-01 measured, focus
    parked on the root scope with no key able to leave it — and
    `ShellTraversalPolicy`, which sorts the shell's chrome ahead of the page so
    the navigation pane is no longer the *last* thing in a cycle it visually
    starts. `RootPageState` wraps the whole `NavigationView` in that group plus
    a `FocusScope` it owns and claims the scope from a post-frame callback in
    `initState` **and** from `onWindowFocus` — the second is the one that
    matters, because alt-tabbing away and back was enough to kill traversal
    again. Nothing below the root scope is ever disturbed, so an open dialog or
    a text box being typed in keeps its focus. The back arrow is now not built
    at all unless it can pop, which removes the dead tab stop (IA-03) and the
    near-white disabled-but-enabled-looking rendering (LN-13) in one go, along
    with a `setState()` that was running *inside* `build()`. The three
    `GestureDetector`s — the AI panel's only entry point among them — are
    buttons, guarded by a tree-wide test that fails if one comes back. On the
    distro row, IA-05's "ring 1,100px away" and IA-06's "two rings at once" are
    the same fluent_ui behaviour twice: the Expander header is a `HoverButton`
    that draws its ring around the chevron alone and lights it whenever *any*
    descendant has focus. The chevron's ring is switched off at the theme, the
    leading buttons and the content re-merge an empty `FocusThemeData` to keep
    theirs, and the row draws its own around the whole card. IA-08 gives the
    safe action the initial focus — Tab, Enter on the delete confirmation used
    to delete. IA-07 is one theme change, not 38 widget changes: `buildAppTheme()`
    builds both brightnesses from one function (the light and dark blocks in
    `main.dart` were near-identical) and widens the ring's inner stroke to match
    its outer one, which is what made it read as a hairline.

  - **FIX-07 — accessible names and honest tooltips: complete (10/10).** One new
    file, `lib/components/named_button.dart`, holds `NamedIconButton`: the
    `MergeSemantics(Tooltip(IconButton))` pair as a widget instead of as eleven
    inline repetitions. It has to be that pair, because a fluent_ui `IconButton`
    opens its own semantics container and a `Tooltip` around one is a sibling node
    rather than a name. Nineteen controls across nine files went through it; the
    eleven in `list_item.dart` that already did it by hand were left as they are,
    since rewriting them would disturb the per-region `FocusTheme` FIX-06 had just
    landed there. IA-09's documented trap turned out to be the tooltip, not the
    missing merge: the editor and terminal pickers sat inside a `Tooltip` whose
    message was the field's own `InfoLabel`, so merging the pair as written would
    have named the *button* "Default editor". Both were ST-14 offenders anyway, so
    deleting them closed the naming and the noise together — eleven tooltips on
    that screen restated the label directly above them and are gone, and the two
    that had something to add (Stop WSL, which shuts down every distro, and Edit
    .wslconfig) were rewritten to say it. IA-10 is three places rather than a
    sweep: an `Icon` carries no name, so the licence table's check/cross column and
    the BETA and NEW pills were silent by construction; the status pills were
    already `Text`. 21 new keys landed in all nine locales with real translations.

  - **FIX-04 — long operations: complete (7/7).** One new file,
    `lib/api/cancellation.dart`, holds the `CancelSignal` a UI control and the
    work it stops both hold; it is not `CancelableOperation`, because what has
    to be cancelled is a child process and a socket reached through a callback
    the worker registers while it owns them, and it is not called `CancelToken`
    because `dio` already exports one into both files that needed it. Create
    now takes a signal end to end: the download is stopped at the socket, the
    `wsl --import` is a killable child rather than a `Process.run`, and the
    cancel path unregisters the half-imported distro — a distro that lists,
    will not start, and whose name cannot be reused is worse than none. Cancel
    is enabled *during* the install instead of being the one labelled exit the
    app took away, and the nav pane, back button and window X now ask (via the
    `UnsavedChangesGuard` FIX-01 landed) rather than silently abandoning the
    page with the install still running. A cancelled download does **not**
    throw — `ChunkedDownloader.stop()` breaks its loop and lets `start()`
    return normally — so reading it as an exception reported the user's own
    cancel as "the server returned an empty file"; it is detected, not caught.
    CI-16's stall is gone because the phase itself moves: the page draws a bar
    with bytes and a transfer rate, and the import reports `Importing 2:14`
    with a null fraction rather than a made-up percentage. CI-13 turned out to
    be that `start` is not a program: `cmd /c start` hands its child to a new
    console and exits, so the `await result.exitCode` already there awaited
    nothing — `start "" /wait` makes it real, the form says a terminal will
    open, and `WSLApi.hasPassword` asks afterwards, because closing that
    window without typing left the account passwordless in silence. 14 new
    keys in all nine locales.

  - **FIX-08 — destructive actions: complete (12/12).** Three of the twelve were
    one control running an irreversible command on a single click with nothing
    in between: Stop WSL (`wsl --shutdown` — every instance on the machine and
    every process inside them), the MCP token refresh, and the chat panel's
    Clear. All three go through the house `dialog()` with a red submit now, and
    the copy names the consequence — which clients stop working, that unsaved
    work inside a running instance is lost. `dialog()` gained a `hostContext`
    parameter to make that possible: `GlobalVariable.infobox` is the *home*
    screen's key, so the settings screen and the chat panel were resolving it
    to an element that is not mounted while they are on screen. ST-38 and
    ST-54 were one string used for three different objects — deleting a saved
    template archive asked "Delete instance test-4 permanently? / If you delete
    this Distro you won't be able to recover it" — so each object got its own
    pair, guarded by a test that fails if the distro strings are referenced
    outside `list_item.dart`. The styling half is one colour and one layout
    call: `destructiveColor()` resolves fluent's per-brightness red brush,
    because the flat `Colors.red` those dialogs submit with is the light-theme
    shade and goes muddy against the dark background. Delete moved out from
    between the broom and the gear — two controls a user reaches for routinely,
    32px away on each side — to last in the row, behind a separator, in that
    colour; and the per-distro dialog's four action buttons, which were
    full-width rows with a 16px glyph on the right (the exact shape of the
    three `wsl.conf` Expanders above them), are content-sized under their own
    heading with the three irreversible ones coloured. ST-46 and CI-31 needed
    words rather than styling: a physical mount needs elevation and takes the
    disk away from Windows, which was only ever said *after* the mount failed,
    and a copy duplicates the whole disk and stops the source first, which was
    not said anywhere.

  - **FIX-09 — one dialog contract: complete (11/11).** The contract is primary
    action filled and first, Cancel last — the order `base_dialog.dart`, the
    create screen and the AI Workspace dialogs already used. The three dialogs
    on the other convention (per-distro settings, mount, community snippets)
    flipped. `dialog()` grew a `placeholder` parameter (the *item* — the
    source's own name — is no longer the input's placeholder, so an empty box
    stops reading as pre-filled, CI-30/ST-43) and a `validateInput` callback
    that runs before the pop and keeps the dialog open with the reason under
    the box. The dead `createDialog()` is deleted. The source-type ComboBox —
    whose popup anchored on the selected item and covered the page title and
    the just-typed name — became a `DropDownButton` whose flyout opens below,
    grouped remote-vs-local with a description line per entry (closes FIX-12's
    CI-26 early). Community dialog: titled, content-sized, primary-first.
    Per-distro dialog: 640x720, titled with the distro name.

  **Next up:** FIX-10 (contrast and theme tokens), then FIX-11. Verification for
  the FIX-09 slice: `flutter analyze` clean (the same two pre-existing warnings,
  untouched), `flutter test` 819 passing (was 815; one flaky timing-dependent
  failure in the streamed-install suite passed on re-run),
  `dart run scripts/check_translations.dart` exit 0. 7 new keys in all nine
  locales. New tests: `test/dialog_contract_test.dart` (4, covering the button
  order, the placeholder, the validate-before-pop contract and the deleted
  `createDialog()`). `flutter test integration_test/` could not be run here — the harness
  builds the app (`Built build\windows\x64\runner\Debug\wsl2distromanager.exe`)
  and then fails with "Unable to start the app on the device" / "The log reader
  stopped unexpectedly", which is the environment, not the change. `dart format`
  was deliberately **not** run: the toolchain here ships the
  3.7 "tall style" formatter and the repo is formatted with the older one, so a
  format pass rewrites every touched file end to end. Edits match the surrounding
  style by hand instead.

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
