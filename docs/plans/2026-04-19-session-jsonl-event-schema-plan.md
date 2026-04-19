# Session JSONL Event Schema Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Make `conversation.jsonl` the durable local event log for sessions, replay,
debugging, and lightweight observability.

This replaces the need for OpenTelemetry/Langfuse as the default local
debugging path. External observability can be removed or kept as an optional
adapter later, but the product should work from JSONL first.

## Current Code Context

Relevant files:

- `lib/src/storage/session_store.dart`
- `lib/src/session/session_manager.dart`
- `lib/src/app/agent_orchestration.dart`
- `lib/src/app/event_router.dart`
- `lib/src/app/session_runtime.dart`
- `lib/src/agent/agent_core.dart`
- `docs/reference/session-storage.md`
- `docs/reference/glue-home-layout.md`
- `lib/src/observability/*`

Current behavior:

- `SessionStore.logEvent(type, data)` appends timestamped JSONL records.
- The append implementation currently reads the whole file and atomically
  rewrites it for every event.
- Common event types are `user_message`, `assistant_message`, `tool_call`,
  `tool_result`, and `title_generated`.
- `SessionManager` reconstructs replay and agent conversation from that narrow
  set.
- Tool result success/failure, pending states, errors, output chunks, model
  metadata, runtime events, file writes, and delegated agent events are not yet
  first-class session events.

## Risks

- Replay will diverge from what the user actually saw.
- Long tool output can make append expensive if the whole JSONL file is
  rewritten every event.
- Observability removal will lose useful debugging data unless JSONL captures
  enough structure.
- Future website/TUI demos may depend on logs that do not have a stable schema.
- Sensitive values can leak into permanent logs unless redaction is explicit.

## Schema Principles

- Append-only.
- One event per line.
- Every event has `schema_version`, `id`, `timestamp`, `session_id`, and `type`.
- Event payloads are typed and small.
- Large blobs go to artifact files and are referenced from JSONL.
- Unknown event types are ignored for replay but preserved for tooling.
- Redaction is represented in the event, not silently hidden.
- Event names are stable and snake_case.

## Base Event Shape

```json
{
  "schema_version": 1,
  "id": "evt_01h...",
  "session_id": "1760000000000-abcd",
  "timestamp": "2026-04-19T12:00:00.000Z",
  "type": "tool_call.started",
  "turn_id": "turn_01h...",
  "seq": 42,
  "data": {}
}
```

Required fields:

- `schema_version`
- `id`
- `session_id`
- `timestamp`
- `type`
- `seq`
- `data`

Optional fields:

- `turn_id`
- `parent_id`
- `agent_id`
- `span_id`
- `level`
- `redactions`

## Event Types

### Session Lifecycle

- `session.started`
- `session.resumed`
- `session.forked`
- `session.ended`
- `session.title_generated`
- `session.summary_updated`

### Turn Lifecycle

- `turn.started`
- `turn.completed`
- `turn.cancelled`
- `turn.failed`

### Messages

- `message.user`
- `message.assistant.started`
- `message.assistant.delta`
- `message.assistant.completed`
- `message.system`

### Model Events

- `model.request.started`
- `model.response.delta`
- `model.response.completed`
- `model.response.failed`
- `model.usage`

### Tool Events

- `tool_call.pending`
- `tool_call.started`
- `tool_call.output`
- `tool_call.completed`
- `tool_call.failed`
- `tool_call.denied`
- `tool_call.cancelled`

### File Events

- `file.read`
- `file.write.started`
- `file.write.diff`
- `file.write.completed`
- `file.write.failed`

### Runtime Events

- `runtime.command.started`
- `runtime.command.output`
- `runtime.command.completed`
- `runtime.command.failed`
- `runtime.command.cancelled`
- `runtime.container.started`
- `runtime.container.stopped`

### Delegated Agent Events

- `agent.delegated`
- `agent.message`
- `agent.tool_call`
- `agent.completed`
- `agent.failed`

### UI Replay Hints

- `ui.group.collapsed`
- `ui.group.expanded`
- `ui.transcript.marker`

UI hints are optional. Replay should still work without them.

## Example Tool Event Sequence

```json
{"schema_version":1,"id":"evt_1","session_id":"s1","timestamp":"2026-04-19T12:00:00.000Z","type":"tool_call.pending","turn_id":"t1","seq":10,"data":{"call_id":"tc1","name":"read_file"}}
{"schema_version":1,"id":"evt_2","session_id":"s1","timestamp":"2026-04-19T12:00:01.000Z","type":"tool_call.started","turn_id":"t1","seq":11,"data":{"call_id":"tc1","name":"read_file","arguments":{"path":"README.md"}}}
{"schema_version":1,"id":"evt_3","session_id":"s1","timestamp":"2026-04-19T12:00:01.200Z","type":"tool_call.output","turn_id":"t1","seq":12,"data":{"call_id":"tc1","stream":"stdout","text":"# Glue\\n"}}
{"schema_version":1,"id":"evt_4","session_id":"s1","timestamp":"2026-04-19T12:00:01.300Z","type":"tool_call.completed","turn_id":"t1","seq":13,"data":{"call_id":"tc1","success":true,"exit_code":0,"duration_ms":300}}
```

## File Layout

Recommended session directory:

```text
~/.glue/sessions/<session-id>/
  meta.json
  conversation.jsonl       # canonical event log
  state.json
  artifacts/
    <event-id>.txt
    <event-id>.json
    <event-id>.patch
    <event-id>.png
```

Use artifacts when:

- output exceeds a configured byte limit
- output is binary
- output is an image
- diff is large
- browser screenshot is captured

JSONL event references:

```json
{
  "type": "tool_call.output",
  "data": {
    "call_id": "tc1",
    "artifact": "artifacts/evt_123.txt",
    "truncated": true,
    "bytes": 1048576
  }
}
```

## Append Implementation

Change `SessionStore.logEvent` so it does not read and rewrite the entire file
on every event.

Preferred implementation:

- open file in append mode
- write one JSON line
- flush if needed for crash safety
- keep atomic writes for `meta.json` and `state.json`

If a fully atomic append abstraction is needed, isolate it behind:

```dart
abstract class SessionEventSink {
  void append(SessionEvent event);
}
```

## Redaction

Add a small redaction pass before events hit disk.

Redact:

- known API key env vars
- provider auth headers
- bearer tokens
- cookies
- common secret patterns
- configured user secrets

Represent redaction:

```json
{
  "type": "tool_call.started",
  "redactions": [
    {"path":"data.arguments.env.OPENAI_API_KEY","reason":"secret"}
  ],
  "data": {
    "arguments": {
      "env": {
        "OPENAI_API_KEY": "[redacted]"
      }
    }
  }
}
```

## Migration Plan

1. Add typed `SessionEvent` classes and JSON serialization.
2. Keep `SessionStore.logEvent(String, Map)` as a compatibility wrapper.
3. Add new event writer that appends instead of rewriting the whole file.
4. Emit new event names alongside old names for one migration period, or teach
   replay to read both.
5. Update `SessionManager._replayEventsIntoAgent` to read the typed event model.
6. Add artifact writer for large output and binary payloads.
7. Remove default OpenTelemetry/Langfuse startup wiring after JSONL has enough
   coverage.
8. Update `docs/reference/session-storage.md`.

## Tests

Add tests for:

- old event replay still works
- new event replay reconstructs messages and tool results
- failed tool events render correctly
- large output writes an artifact reference
- corrupt JSONL line is skipped with debug warning
- unknown future event type is ignored
- redaction replaces secrets before disk write
- append does not rewrite existing file contents
- fork preserves event order and creates new session metadata

## Acceptance Criteria

- JSONL is sufficient to replay a realistic session with tool calls, failures,
  file writes, and delegated agent updates.
- Removing OTel/Langfuse does not remove local debugging value.
- Long-running sessions do not slow down because every event rewrites the file.
- Secrets are not knowingly written to session logs.
- Current sessions still resume.

## Open Questions

- Should assistant streaming deltas be persisted, or only final assistant
  messages plus optional deltas for replay?
- Should command output be chunked by bytes or by lines?
- Should artifacts be garbage-collected with their session only, or shared by
  content hash?
- Should replay use UI hint events, or derive collapse groups from tool/agent
  structure every time?
