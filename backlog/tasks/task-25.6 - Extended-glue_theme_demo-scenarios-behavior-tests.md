---
id: TASK-25.6
title: Extended glue_theme_demo scenarios + behavior tests
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
updated_date: '2026-04-19 04:02'
labels:
  - tui-contract-2026-04
  - testing
dependencies:
  - TASK-25.1
  - TASK-25.2
  - TASK-25.3
  - TASK-25.4
  - TASK-25.5
references:
  - cli/bin/glue_theme_demo.dart
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
parent_task_id: TASK-25
priority: low
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`bin/glue_theme_demo.dart` remains the visual regression target — extend it to cover BEHAVIOR as well as theme.

**Scenarios to add:**
- Resize narrow / wide
- Long user prompt wrapping
- Long assistant markdown with table / code / list
- Tool pending / running / succeeded / failed / denied / cancelled (all seven states)
- Streamed command output
- Collapsed / expanded delegated agent block
- File write diff
- No-color mode (`NO_COLOR=1`)
- ASCII fallback mode (`GLUE_ASCII=1`)
- Spinner animation in active states

**Files:**
- Modify: `cli/bin/glue_theme_demo.dart` — add scenario flags or menu
- Add behavior tests (not just visual): wrapping, truncation, scroll anchoring, tool state rendering
- Consider: snapshot-style tests where scripted output compares against golden text (optional, if feasible)

**Depends on:** T1–T5 (all behavior primitives must exist first).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Demo covers all scenarios listed in plan
- [ ] #2 Resize preserves scroll position (tested in demo + unit)
- [ ] #3 All seven tool states render with distinct markers in demo
- [ ] #4 No-color and ASCII fallback modes demonstrable
- [ ] #5 Spinner animation visible only during active states
- [ ] #6 Behavior tests exist for wrapping, truncation, scroll anchoring, tool state rendering
<!-- AC:END -->
