# Phase 07: Full Click-Through UI/UX Audit with Screenshots

This phase walks the entire application by clicking through it in a running build, capturing a screenshot of every screen, dialog and meaningful state, and recording UI/UX problems in a structured, navigable audit. Be **nitpicky**: misaligned spacing, inconsistent button order, truncated or overflowing labels, sentence-case versus title-case drift, grey-on-dark text, disabled controls with no explanation, destructive actions without confirmation, spinners with no cancel, empty states with no guidance, and any string that reads like it was written for a developer. Findings are recorded here; Phase 08 fixes them.

Screenshots go to `.maestro/screenshots/phase-07/` (gitignored, never committed). Findings go to `doc/audit/ui-ux/` (committed). Use the `.maestro/tools/` helpers from Phase 01 and remember the two traps: other windows steal focus, and `resize.ps1` must use `MoveWindow` rather than `ShowWindow(SW_RESTORE)`.

## Tasks

- [ ] Set up a reproducible audit run:
  - Launch with `flutter run -d windows --dart-define=WSLM_FORCE_PRO=true` so Pro surfaces are reachable
  - Kill the app process before touching `shared_preferences.json` — the app overwrites it on exit, so prefs edits made while it runs are lost
  - Fix the window to a known size via `resize.ps1` (use both a 1400×860 "standard" pass and a deliberately narrow ~900px-wide pass) so screenshots are comparable
  - Create `doc/audit/ui-ux/index.md` with YAML front matter (`type: analysis`, `title: UI/UX Click-Through Audit`, `created: 2026-08-28`, `tags: [ui, ux, audit]`) and a findings table that later files link back to

- [ ] Audit the main list and navigation surface, capturing screenshots of each state:
  - `lib/components/list.dart` / `list_item.dart`: running vs stopped distro rows, the 5-second poll not causing visible flicker, hover and focus states, action button order and iconography, long distro names, a machine with zero distros (empty state)
  - `lib/nav/panelist.dart` sidebar: labels, selected state, `PaneItem.title` must be a real `Text` or the entry has no accessible name
  - Window title bar, theme switch, and the app's behaviour at the narrow width
  - Write findings to `doc/audit/ui-ux/list-and-navigation.md` with front matter, one finding per row: what, where (`file:line`), severity, and the screenshot filename

- [ ] Audit the create and install flows:
  - `lib/screens/create_screen.dart` (the new dedicated screen): field order, validation messages, what happens with an empty name, a duplicate name, a name with spaces or non-ASCII characters, the catalogue dropdown, the custom-rootfs path, install progress, cancel, and the error/retry state
  - `lib/dialogs/install_dialog.dart`, `copy_dialog.dart`, `qa_dialog.dart`: consistency with the screen, button order, destructive-action confirmation
  - Write `doc/audit/ui-ux/create-and-install.md`

- [ ] Audit settings, templates, mount and actions:
  - `lib/screens/settings_screen.dart` including everything Phase 05 added: grouping, scroll length, tooltip legibility, which controls need `wsl --shutdown` to take effect and whether the UI says so, save/discard affordances, and whether an invalid value can be saved
  - `lib/dialogs/settings_dialog.dart` per-distro settings; `lib/screens/template_screen.dart`; `lib/dialogs/mount_dialog.dart`; `lib/screens/actions_screen.dart`; `lib/components/qa_list.dart`
  - Write `doc/audit/ui-ux/settings-and-tools.md`

- [ ] Audit the Pro surfaces:
  - `lib/screens/ai_workspace_screen.dart`: card layout, the four lifecycle states, error text legibility, progress visibility, dashboard buttons
  - `lib/screens/license_screen.dart`, `lib/components/pro_badge.dart`, `lib/components/beta_badge.dart`: how Pro gating is communicated to a free user — is it clear what they get, without nagging?
  - `lib/components/ai_chat_panel.dart`, `recommendations_panel.dart`, `ai_diagnosis.dart`, and the MCP server surface
  - Write `doc/audit/ui-ux/pro-surfaces.md`

- [ ] Audit theme, locale and text quality — the highest-yield nitpicking:
  - Repeat the main screens in **dark and light** themes and diff the screenshots; flag any hardcoded `Colors.grey`, any low-contrast text, and any icon that disappears against its background
  - Switch through **all nine locales** (de, en, es, hu, ja, pt, tr, zh_CN, zh_TW); capture at least the home, create and settings screens per locale, and flag every truncated label, overflowing button, untranslated English string and machine-translated phrase that reads wrong
  - Verify no locale blanks the app (the `zh_TW`/`zh_HK` class of bug) and that `test/locales_test.dart` still guards the invariant
  - Write `doc/audit/ui-ux/theme-and-locales.md`

- [ ] Audit interaction and accessibility details:
  - Tab order and keyboard reachability on every screen; can a keyboard-only user create, start, stop and delete a distro?
  - Tooltips on icon-only buttons — a fluent_ui `Tooltip` cannot label a `BaseButton` because `IconButton` opens its own semantics container; the fix is `MergeSemantics` around the pair, so flag every icon button lacking it
  - Long-running operations: is there always a spinner, a cancel and an error path? Does anything lock the whole UI unnecessarily?
  - Error text quality: flag every message containing a raw exception, a bare colon, a stack trace or a shell command a user cannot act on
  - Write `doc/audit/ui-ux/interaction-and-a11y.md`

- [ ] Consolidate the findings into `doc/audit/ui-ux/index.md`:
  - One table of every finding, cross-linked with `[[list-and-navigation]]`-style wiki-links to the per-area files
  - Severity (blocker / major / nit) and an effort estimate for each
  - An explicit ordered fix list, most impactful first — this is the input to Phase 08 and must be complete
  - A short "not examined" section for anything skipped (e.g. remote WSL over SSH if no second machine is available), so the audit does not imply coverage it does not have
