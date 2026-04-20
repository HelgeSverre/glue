---
id: TASK-37
title: Session JSONL event schema expansion
status: To Do
assignee: []
created_date: '2026-04-20 00:08'
updated_date: '2026-04-20 00:32'
labels:
  - sessions
  - observability
  - schema
milestone: m-0
dependencies: []
references:
  - cli/lib/src/storage/session_store.dart
  - cli/lib/src/session/session_manager.dart
  - cli/lib/src/app/event_router.dart
  - cli/lib/src/agent/agent_core.dart
documentation:
  - docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
  - docs/reference/session-storage.md
priority: medium
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make `conversation.jsonl` the durable local event log for sessions, replay, debugging, and lightweight observability — replacing the need for OpenTelemetry/Langfuse as the *default* local debugging path.

**Per the plan (`docs/plans/2026-04-19-session-jsonl-event-schema-plan.md`):**

Today `SessionStore.logEvent(type, data)` writes a narrow set of types: `user_message`, `assistant_message`, `tool_call`, `tool_result`, `title_generated`. The plan expands this to record:

- Tool result success/failure, pending states, errors, output chunks
- Model metadata
- Runtime events (where the command ran, container ID)
- File writes (delta info — depends on TASK-19)
- Delegated agent events (subagent lifecycle)
- UI group collapse/expand events (for replay state restoration)

**Key structural changes:**
- `SessionStore` append currently rewrites the whole file — should switch to true append for performance.
- Event names align with TASK-25.4 canonical tool states (`tool_call.{pending,started,output,completed,failed,denied,cancelled}`).
- Schema versioning so consumers can degrade gracefully.

**Coordinates with:**
- TASK-25.4 (tool display states) — must use the same vocabulary.
- TASK-26 (runtime boundary) — runtime events depend on this schema.
- TASK-27 (session replay UI) — primary consumer.
- TASK-19 (diff-aware write/edit metadata) — feeds file write events.

**Why now:** Several downstream tasks reference SE1–SE4 from this plan as a precondition. Land the schema before they need it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Expanded event schema documented in `docs/reference/session-storage.md` with versioning rules.
- [ ] #2 Tool call events follow canonical state names from TASK-25.4 (`pending` / `started` / `output` / `completed` / `failed` / `denied` / `cancelled`).
- [ ] #3 Subagent lifecycle events recorded (start, tool calls, completion).
- [ ] #4 Runtime events capture where commands ran (host / docker / future cloud) — depends on TASK-26.
- [ ] #5 Append path no longer rewrites the whole file each event (true append).
- [ ] #6 Schema version field present; older sessions read with permissive defaults.
- [ ] #7 TASK-27 (replay) and TASK-25.4 (tool states) both validate against the new schema.
<!-- AC:END -->
