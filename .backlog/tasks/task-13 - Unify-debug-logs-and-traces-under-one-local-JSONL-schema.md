---
id: TASK-13
title: Unify debug logs and traces under one local JSONL schema
status: To Do
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 00:43'
labels:
  - simplification-2026-04
  - observability
  - refactor
dependencies:
  - TASK-11
references:
  - cli/lib/src/observability/observability.dart
  - cli/lib/src/observability/file_sink.dart
  - cli/lib/src/storage/session_store.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After R4 removes external telemetry, two overlapping local systems remain: `FileSink` (writes `spans-YYYY-MM-DD.jsonl`) and `SessionStore` (writes `conversation.jsonl` + `meta.json`). Unify on one event schema so cross-cutting queries (grep/jq across logs) work cleanly.

**Why:** Today: logs, traces, observability sinks, session logs all have slightly different shapes. After external telemetry is gone, define one local event schema and write all debug/runtime events as JSONL through that schema.

**Target file layout:**
```
~/.glue/
  logs/
    glue-debug-YYYY-MM-DD.jsonl    # cross-session debug
  traces/
    <session-id>.jsonl              # per-session trace
  sessions/
    <session-id>/
      meta.json                     # session metadata (unchanged — user-visible)
      conversation.jsonl            # user+assistant messages (unchanged)
```

**Event record shape:**
```json
{
  "ts": "2026-04-19T12:34:56Z",
  "type": "llm_start|llm_usage|tool_start|tool_end|error",
  "session_id": "...",
  "trace_id": "...",
  "span_id": "...",
  "attributes": { ... }
}
```

**Files to modify:**
- `cli/lib/src/observability/observability.dart` — extend `ObservabilitySpan` with a `type` discriminator OR introduce a sibling `Event` type; preserve the existing snake_case serialization contract (per ISSUES.md NAME-008)
- `cli/lib/src/observability/file_sink.dart` — route per-session spans to `~/.glue/traces/<session-id>.jsonl` in addition to daily debug file
- `cli/lib/src/storage/session_store.dart` — leave `meta.json` and `conversation.jsonl` as user-facing artifacts; do NOT merge them into traces
- Tests: add round-trip + per-session routing tests

**Depends on:** R4 (external observability removed first so schema change is not perturbed by OTEL exporter contracts).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Single event type serialized by `FileSink` (discriminator field present)
- [ ] #2 Per-session trace file written under `~/.glue/traces/<session_id>.jsonl`
- [ ] #3 Global daily debug file still written under `~/.glue/logs/`
- [ ] #4 `SessionMeta` and `conversation.jsonl` schemas untouched
- [ ] #5 Tests cover event round-trip and per-session routing
- [ ] #6 `dart test test/observability` green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Scope narrowed by new SE parent (task-24). M1 handles only the `~/.glue/logs/` + `~/.glue/traces/` FileSink file layout. Per-session event semantics (rich event types, redaction, artifacts, append-only writer) are handled by task-24 and its subtasks (24.1–24.5). If SE1–SE3 absorb M1's goals entirely, close this task as superseded when those land.
<!-- SECTION:NOTES:END -->
