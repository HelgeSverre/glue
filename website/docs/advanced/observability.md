# Observability

Glue writes spans and debug events to local JSONL files, and can also export
the same spans to any OTLP/HTTP-compatible collector (Phoenix, Tempo, Jaeger,
Honeycomb, etc.).

## Debug Logging

Toggle verbose logging during a session with `/debug`, or start with `--debug`
/ `GLUE_DEBUG=1`. Span records are written to daily JSONL files in
`~/.glue/logs/spans-YYYY-MM-DD.jsonl`.

::: tip
Debug logging is useful for inspecting prompt assembly, tool calls, and
token usage. Use `jq` or `grep` on the JSONL files to slice the stream.
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
  "attributes": {}
}
```

## OpenTelemetry export

When an OTLP endpoint is configured, the same spans are forwarded to a
collector via an `OtlpHttpTraceSink`. Spans flush every 5 seconds while a
session is running.

Configure under `observability.otel` in `~/.glue/config.yaml`:

```yaml
observability:
  debug: false
  max_body_bytes: 65536
  redact: true
  otel:
    enabled: true
    endpoint: https://app.phoenix.arize.com/s/your-space
    headers:
      Authorization: Bearer <token>
    service_name: glue
    resource_attributes:
      openinference.project.name: glue
```

### Supported config keys

| Key                                      | Type    | Notes                                                              |
| ---------------------------------------- | ------- | ------------------------------------------------------------------ |
| `observability.otel.enabled`             | boolean | Defaults to on when an endpoint is set and `OTEL_SDK_DISABLED` ≠ 1 |
| `observability.otel.endpoint`            | string  | OTLP/HTTP traces endpoint                                          |
| `observability.otel.headers`             | map     | Sent on every export request (auth tokens, project headers)        |
| `observability.otel.service_name`        | string  | Defaults to `glue`                                                 |
| `observability.otel.resource_attributes` | map     | Merged into the OTLP `Resource` block                              |

### Environment-variable fallbacks

If a key is not set in `config.yaml`, Glue reads the standard OTEL env vars:

| Setting            | Environment variables (first match wins)                                                   |
| ------------------ | ------------------------------------------------------------------------------------------ |
| Endpoint           | `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `PHOENIX_COLLECTOR_ENDPOINT` |
| Headers            | `OTEL_EXPORTER_OTLP_TRACES_HEADERS`, `OTEL_EXPORTER_OTLP_HEADERS`, `PHOENIX_API_KEY`       |
| Service name       | `OTEL_SERVICE_NAME`                                                                        |
| Resource attrs     | `OTEL_RESOURCE_ATTRIBUTES`, `PHOENIX_PROJECT_NAME`                                         |
| Master kill switch | `OTEL_SDK_DISABLED=1` disables export even when an endpoint is set                         |

`PHOENIX_PROJECT_NAME`, when set, is mapped to the
`openinference.project.name` resource attribute (and a default of `glue` is
applied if nothing else provides one) so traces show up under the expected
Phoenix project.

A richer per-session event schema (messages, tool calls, runtime events) is
being introduced separately — see the session JSONL schema plan.

## See also

- [ObservabilityConfig](/api/observability/observability-config)
- [DebugController](/api/observability/debug-controller)
- [FileSink](/api/observability/file-sink)
