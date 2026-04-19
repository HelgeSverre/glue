---
id: TASK-25.4
title: Tool display states + transcript groups (collapse/expand)
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
labels:
  - tui-contract-2026-04
  - rendering
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
parent_task_id: TASK-25
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Normalize tool rendering around canonical states and make long transcript blocks collapsible/expandable.

**Canonical tool states** (align with SE event schema `tool_call.{pending,started,output,completed,failed,denied,cancelled}`):
- `pending` — model has named a tool but args still streaming
- `awaitingApproval` — user decision required
- `running` — Glue is executing the tool
- `succeeded` — tool completed successfully
- `failed` — tool completed with error
- `denied` — user or policy denied execution
- `cancelled` — user cancelled while active

**Each state should render:**
- Compact collapsed header
- Expanded arguments
- Streamed output chunks
- Final output
- stderr/error summary
- File write diff (if applicable)
- Artifact link for long output (from SE4)

**Transcript groups (collapsible):**
- Tool call + result pair
- Delegated agent transcript
- Long command output
- File write diff
- Very long markdown assistant response

**Rules:**
- Collapsed summary fits on one or two lines
- Expanded state is keyboard + mouse accessible
- Collapsed state persists during session (memory only for now)
- Session JSONL `ui.group.{collapsed,expanded}` events (SE1) optionally restore state on replay

**Files:**
- Modify: `cli/lib/src/rendering/block_renderer.dart` or `tool_block.dart`
- Create: `cli/lib/src/rendering/transcript_group.dart`
- Keybinding: decide expand/collapse key (open question in plan; candidate: `Ctrl+Space` or `Space` when focused)

**Coordinates with:** SE1 (event state names) + SE3 (emission).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Seven tool states render with distinct semantic markers
- [ ] #2 Each state has both compact and expanded rendering
- [ ] #3 Transcript groups (tool, agent, long-output, file-diff) support collapse/expand
- [ ] #4 Collapsed summary fits in 1–2 lines
- [ ] #5 Expand/collapse works via both keyboard and mouse
- [ ] #6 Tool state names align with SE event schema (task-24.1)
- [ ] #7 Tests cover each state transition + collapse/expand
<!-- AC:END -->
