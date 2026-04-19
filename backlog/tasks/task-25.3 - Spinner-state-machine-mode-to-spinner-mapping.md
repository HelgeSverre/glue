---
id: TASK-25.3
title: Spinner state machine (mode-to-spinner mapping)
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
updated_date: '2026-04-19 04:02'
labels:
  - tui-contract-2026-04
  - state-machine
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
parent_task_id: TASK-25
priority: medium
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Spinner today animates but the mapping between app mode and spinner state is implicit. Make it explicit so the spinner never gets stuck.

**Rules (from plan):**
- Spinner only animates while work is actually active
- Streaming text ("thinking" / "writing"): spinner may animate
- Tool running: show tool state; keep spinner separate or paused
- Waiting for user approval: no spinner; show approval state
- Background job running: show job state, not model spinner
- Spinner frame ticks on a timer INDEPENDENT of incoming tokens
- Timer MUST stop when mode returns to idle

**Target:**
- Explicit state machine: `idle → thinking → streaming → toolRunning → awaitingApproval → idle`
- One place that maps mode → spinner-on/off
- Timer lifecycle owned by the mapping

**Files:**
- Modify: `cli/lib/src/app/render_pipeline.dart` (look for `_spinnerFrames`, `_startSpinner`, `_stopSpinner`)
- Create: `cli/lib/src/app/spinner_state.dart` — explicit state machine
- Tests: spinner starts/stops with mode changes; timer stops when idle
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Explicit spinner state machine documented + implemented
- [ ] #2 Spinner only animates during active work
- [ ] #3 Waiting for user approval: no spinner; approval state shown instead
- [ ] #4 Tool running: tool state rendered, spinner paused or independent
- [ ] #5 Timer stops cleanly when mode returns to idle (no stuck spinner)
- [ ] #6 Background jobs show job state, not model spinner
- [ ] #7 Tests verify each transition and timer lifecycle
<!-- AC:END -->
