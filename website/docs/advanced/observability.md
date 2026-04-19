# Observability

Glue logs spans and debug events to local JSONL files. External telemetry exporters (OpenTelemetry, Langfuse, DevTools sink) were removed — the single source of truth is `~/.glue/logs/`.

## Debug Logging

Toggle verbose logging during a session with `/debug`, or start with `--debug` / `GLUE_DEBUG=1`. Span records are written to daily JSONL files in `~/.glue/logs/spans-YYYY-MM-DD.jsonl`.

::: tip
Debug logging is useful for inspecting prompt assembly, tool calls, and token usage. Use `jq` or `grep` on the JSONL files to slice the stream.
:::

## Local JSONL schema

Each span is serialized with snake_case keys:

```json
{
  "trace_id": "...",
  "span_id": "...",
  "parent_span_id": "...",
  "name": "llm.stream",
  "kind": "llm",
  "start_time": "2026-04-19T12:00:00.000Z",
  "end_time": "2026-04-19T12:00:01.234Z",
  "duration_ms": 1234,
  "attributes": { }
}
```

A richer per-session event schema (messages, tool calls, runtime events) is being introduced separately — see the session JSONL schema plan.

## See also

- [ObservabilityConfig](/api/observability/observability-config)
- [DebugController](/api/observability/debug-controller)
- [FileSink](/api/observability/file-sink)
