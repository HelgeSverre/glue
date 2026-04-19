---
id: TASK-25.1
title: TranscriptModel + scroll anchor (resize-safe)
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
updated_date: '2026-04-19 04:02'
labels:
  - tui-contract-2026-04
  - refactor
dependencies: []
references:
  - cli/lib/src/app/render_pipeline.dart
  - cli/lib/src/app/terminal_event_router.dart
documentation:
  - cli/docs/plans/2026-04-19-tui-behavior-contract-plan.md
parent_task_id: TASK-25
priority: medium
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Introduce a `TranscriptModel` abstraction between `_blocks` and rendered lines. Track a scroll anchor (not just an integer offset) so resize preserves the user's position.

**Why:** today resize clears the screen, reapplies layout, resets scroll offset to bottom. That loses the user's context when they were scrolled up reading a long tool output.

**Target behavior:**
- PageUp/PageDown scroll by half viewport
- Mouse wheel scrolls when pointer over output
- New output follows tail unless user has scrolled up
- When scrolled up, status hint like `up 42` visible
- `End` key jumps to bottom
- Resize rewraps all visible transcript blocks AND keeps the same transcript anchor when possible
- Input cursor must remain visible after resize

**State machine addition:** explicit `FollowTail` state (distinct from "scroll offset 0"). Scrolling up disengages FollowTail; `End` re-engages it.

**Files:**
- Create: `cli/lib/src/app/transcript_model.dart`
- Modify: `cli/lib/src/app/render_pipeline.dart` — consume model
- Modify: `cli/lib/src/app/terminal_event_router.dart` — wire `End` key, adjust PageUp/PageDown
- Tests: resize preserves scroll position when scrolled up; resize follows tail when at bottom
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `TranscriptModel` class exists
- [ ] #2 Resize preserves scroll position when user is scrolled up
- [ ] #3 Resize follows tail when user was at bottom
- [ ] #4 `End` key jumps to bottom and re-engages FollowTail
- [ ] #5 PageUp/PageDown scroll by half viewport
- [ ] #6 `up N` status hint shown when scrolled up
- [ ] #7 Input cursor remains visible after resize
- [ ] #8 Tests cover resize behavior in both anchored and FollowTail modes
<!-- AC:END -->
