---
id: TASK-27
title: Session replay UI for JSONL logs
status: To Do
assignee: []
created_date: '2026-04-19 05:00'
updated_date: '2026-04-20 00:05'
labels:
  - sessions
  - ui
  - roadmap-later
milestone: m-3
dependencies:
  - TASK-25
  - TASK-18
documentation:
  - docs/reference/session-storage.md
  - docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
priority: medium
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a dedicated replay surface that reads `~/.glue/sessions/<id>/conversation.jsonl`
and renders the session step-by-step with the same block format Glue shows
live. Sessions are already append-only JSONL today; this task adds the
playback UI on top.

**Entry points:**
- `glue replay <session-id>` — opens the session in replay mode.
- `glue replay --last` — most recent session in the current workspace.
- From inside the TUI: `/replay <id>` slash command.

**Replay surface:**
- Event log rendered via `BlockRenderer` (same renderer the live TUI uses).
- Scrubbable timeline: keyboard ← → step-by-step, ⇧← ⇧→ jump by
  tool-call group, Home/End jump to start/end.
- Tool-call groups collapse/expand with the existing
  `_EntryKind.subagentGroup` UI.
- Status bar: event index, total events, wall-clock timestamp, model in use
  at this point in the session.
- Diff rendering for `edit` tool results (re-use whatever write/edit diff
  rendering TASK-19 produces).
- Optional: export range to a gist/markdown via `/export` — out of scope
  for the first cut.

**Non-goals (for now):**
- No server-side replay, no hosted dashboard (Glue stays local-first).
- No multi-session timeline/browser — single session at a time.
- No editing/annotating events — playback only.

**Dependencies / order:**
- TASK-25 (TUI behavior contract) pins the behavior we need to replay
  deterministically.
- TASK-18 (standardized tool result schema) makes it safe to render old
  sessions without special-casing.
- The expanded session JSONL schema (see plan) is ideal but not required —
  replay should gracefully degrade on the narrower event set in use today.

**Files (anticipated):**
- `cli/lib/src/replay/replay_controller.dart` — loads + walks the JSONL.
- `cli/lib/src/replay/replay_app.dart` — TUI entry point, keybinds.
- `cli/lib/src/commands/builtin_commands.dart` — `/replay` registration.
- `cli/bin/glue.dart` — CLI arg plumbing for `glue replay`.

**Website/roadmap:** already listed as `planned` on `/roadmap` under
*Later*. Promote to *Next* when the TUI behavior contract ships.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `glue replay <session-id>` loads and renders an existing
      `conversation.jsonl` end-to-end without errors.
- [ ] #2 `glue replay --last` picks the most recent session rooted at the
      current workspace.
- [ ] #3 Playback uses `BlockRenderer` — no divergent formatting between
      live and replay.
- [ ] #4 Keyboard: ← / → step one event; ⇧← / ⇧→ jump by tool-call group;
      Home / End jump to ends; `q` or Esc exits.
- [ ] #5 Status bar shows: event index / total, timestamp, model, source
      path.
- [ ] #6 Replays a session recorded with the current narrow event schema
      AND one recorded with the expanded schema (once TASK-25 and the
      JSONL schema plan land).
- [ ] #7 Works offline — no network calls during replay.
- [ ] #8 Handles a corrupted trailing line gracefully (skip + warn at the
      status bar, continue replay).
<!-- AC:END -->



## Notes

- Keep the controller pure so it can drive a future web-based replay in
  TASK-6 (ACP web UI) without rewriting the walker.
- Do not add a "re-run the tool calls" feature. Replay is read-only; real
  re-execution belongs in a separate task and has different security
  semantics.
