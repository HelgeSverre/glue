---
id: TASK-25.5
title: Input focus priority + key bindings
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
updated_date: '2026-04-20 00:05'
labels:
  - tui-contract-2026-04
  - input
milestone: m-1
dependencies: []
references:
  - cli/lib/src/app/terminal_event_router.dart
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
parent_task_id: TASK-25
priority: low
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document and enforce a clear focus priority and key-binding contract.

**Focus priority (top wins):**
1. Modal (e.g., confirmation dialog)
2. Active panel
3. Autocomplete overlay
4. File hint
5. Shell completion
6. Editor (input)

**Key bindings:**
- `Esc` — close the focused transient UI first; if nothing to close, do nothing (don't quit)
- Single `Ctrl+C` — cancel active work OR prompt exit in idle mode
- Double `Ctrl+C` — exit immediately
- Bracketed paste — insert text without triggering commands mid-paste
- `Shift+Enter` — insert newline when terminal reports it (not all terminals support this)
- `Enter` — submit unless autocomplete/panel consumes it

**Files:**
- Modify: `cli/lib/src/app/terminal_event_router.dart`
- Tests: focus priority order + each key-binding behavior

**Coordinates with:** M10 (unified AutocompleteOverlay) — focus priority assumes a consistent autocomplete interface.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Focus priority documented in code + enforced in event router
- [ ] #2 `Esc` closes focused transient UI first
- [ ] #3 Double `Ctrl+C` exits; single `Ctrl+C` cancels or prompts exit by mode
- [ ] #4 Bracketed paste does not trigger mid-paste commands
- [ ] #5 `Shift+Enter` inserts newline when terminal reports it
- [ ] #6 `Enter` submits unless overlay consumes it
- [ ] #7 Tests cover focus priority under each focus combination
<!-- AC:END -->
