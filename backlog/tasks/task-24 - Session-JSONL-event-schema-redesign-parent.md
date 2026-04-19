---
id: TASK-24
title: Session JSONL event schema redesign (parent)
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
labels:
  - session-jsonl-2026-04
  - parent
  - observability
dependencies: []
references:
  - cli/lib/src/storage/session_store.dart
  - cli/lib/src/session/session_manager.dart
  - cli/lib/src/app/agent_orchestration.dart
documentation:
  - cli/docs/plans/2026-04-19-session-jsonl-event-schema-plan.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make `conversation.jsonl` the durable local event log for sessions, replay, debugging, and lightweight observability. This is the local replacement for OpenTelemetry/Langfuse that R4 removes.

**Why:** Today `SessionStore.logEvent(type, data)` appends timestamped JSONL, but the append implementation reads the whole file and atomically rewrites it for every event (performance cliff). Schema is narrow (`user_message`, `assistant_message`, `tool_call`, `tool_result`, `title_generated`). Tool success/failure/pending, output chunks, model metadata, runtime events, file writes, delegated agents are not first-class.

**Schema principles:**
- Append-only; one event per line
- Every event: `schema_version`, `id`, `timestamp`, `session_id`, `type`, `seq`, `data`
- Optional: `turn_id`, `parent_id`, `agent_id`, `span_id`, `level`, `redactions`
- Large blobs → artifact files, referenced from JSONL
- Unknown event types ignored for replay, preserved for tooling
- Redaction represented in the event, not silently hidden
- Event names stable, snake_case

**Event type families:**
- Session lifecycle (started/resumed/forked/ended/title_generated/summary_updated)
- Turn lifecycle (started/completed/cancelled/failed)
- Messages (user/assistant.{started,delta,completed}/system)
- Model events (request.started/response.{delta,completed,failed}/usage)
- Tool events (pending/started/output/completed/failed/denied/cancelled)
- File events (read/write.{started,diff,completed,failed})
- Runtime events (command.{started,output,completed,failed,cancelled}/container.{started,stopped})
- Delegated agent events (delegated/message/tool_call/completed/failed)
- UI replay hints (group.collapsed/expanded, transcript.marker)

**Supersedes scope of M1 (unified FileSink logs)** — M1 is narrowed to just the `~/.glue/logs/` + `~/.glue/traces/` file layout; this parent handles per-session event semantics.

**Subtasks:** SE1–SE5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 JSONL can replay a realistic session with tool calls, failures, file writes, and delegated agents
- [ ] #2 Removing OTel/Langfuse (R4) does not lose local debugging value
- [ ] #3 Long-running sessions do not slow down — no whole-file rewrite per event
- [ ] #4 Secrets are not knowingly written (redaction pass in place)
- [ ] #5 Current sessions still resume (backward compatible)
- [ ] #6 All subtasks SE1–SE5 complete
<!-- AC:END -->
