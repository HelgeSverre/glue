---
id: TASK-24.1
title: Typed SessionEvent classes + JSON serialization
status: To Do
assignee: []
created_date: '2026-04-19 00:42'
labels:
  - session-jsonl-2026-04
  - schema
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
parent_task_id: TASK-24
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Define typed Dart classes for the new session event schema and their JSON (de)serialization.

**Base event (required fields):**
```
schema_version, id, session_id, timestamp, type, seq, data
```

**Optional fields:** `turn_id`, `parent_id`, `agent_id`, `span_id`, `level`, `redactions`

**Event-type families (sealed hierarchy):**
- Session lifecycle: `session.{started,resumed,forked,ended,title_generated,summary_updated}`
- Turn lifecycle: `turn.{started,completed,cancelled,failed}`
- Messages: `message.user`, `message.assistant.{started,delta,completed}`, `message.system`
- Model: `model.request.started`, `model.response.{delta,completed,failed}`, `model.usage`
- Tool: `tool_call.{pending,started,output,completed,failed,denied,cancelled}`
- File: `file.read`, `file.write.{started,diff,completed,failed}`
- Runtime: `runtime.command.{started,output,completed,failed,cancelled}`, `runtime.container.{started,stopped}`
- Delegated agent: `agent.{delegated,message,tool_call,completed,failed}`
- UI hints: `ui.group.{collapsed,expanded}`, `ui.transcript.marker`

**Files to create:**
- `cli/lib/src/session/events/session_event.dart` — base + sealed hierarchy
- `cli/lib/src/session/events/tool_events.dart`, `file_events.dart`, `runtime_events.dart`, `model_events.dart`, `agent_events.dart`, `ui_events.dart`
- `cli/test/session/events/session_event_test.dart`

**Principles:** event names stable, snake_case; unknown types preserved for tooling (not lost on round-trip); JSON serialization matches base shape exactly.

**Cross-reference:** tool state names must match the TUI behavior contract (task-25) states.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sealed event hierarchy covers all families listed in plan
- [ ] #2 Every event has required base fields (schema_version, id, session_id, timestamp, type, seq, data)
- [ ] #3 Optional fields supported (turn_id, parent_id, agent_id, span_id, level, redactions)
- [ ] #4 JSON round-trip preserves unknown event types
- [ ] #5 Event names use stable snake_case
- [ ] #6 Tool state names align with TUI behavior contract (task-25)
- [ ] #7 Tests cover round-trip for every event type
<!-- AC:END -->
