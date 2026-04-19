---
id: TASK-25
title: TUI behavior contract (parent)
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 04:02'
labels:
  - tui-contract-2026-04
  - parent
  - tui
dependencies: []
references:
  - cli/lib/src/terminal/terminal.dart
  - cli/lib/src/terminal/layout.dart
  - cli/lib/src/app/render_pipeline.dart
  - cli/lib/src/app/terminal_event_router.dart
  - cli/bin/glue_theme_demo.dart
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Define how Glue's TUI behaves (not just how it looks). The theme system and demo are useful, but the implementation needs a behavior contract for wrapping, resize, scrollback, alternate screen, tool states, spinner, keyboard focus, and transcript grouping.

**Product-level decisions (from plan):**
- Alternate screen stays default (add `--no-alt-screen` later)
- Internal scrollback canonical during interactive mode; `End` jumps to bottom; show `up N` indicator when user has scrolled up
- Resize preserves scroll anchor (current reset-to-bottom is too aggressive)
- Wrap by display width (not code unit count); ANSI escapes don't count; wide glyphs = width 2
- Single-cell symbols for controls/state markers; ASCII fallback for every semantic symbol; no Nerd Fonts required
- Spinner only animates during active work — explicit state machine
- Tool states: `pending`, `awaiting approval`, `running`, `succeeded`, `failed`, `denied`, `cancelled`
- Transcript groups: tool call+result, delegated agent, long command output, file write diff — collapsed/expanded state
- Input focus priority: modal > active panel > autocomplete > file hint > shell completion > editor

**Subtasks:** T1–T6 (TranscriptModel+scroll anchor, wrapping+glyphs, spinner state machine, tool display states+groups, input focus, extended demo+tests).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Behavior is predictable across narrow and wide terminals
- [ ] #2 TUI state understandable without relying on color alone
- [ ] #3 User can scroll, resize, expand groups without losing context
- [ ] #4 Working spinner does not get stuck
- [ ] #5 Tool and delegated agent states match what is persisted in JSONL (aligns with SE schema)
- [ ] #6 All T1–T6 subtasks complete
<!-- AC:END -->
