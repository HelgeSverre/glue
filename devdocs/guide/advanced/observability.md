# Observability

Glue supports debug logging and distributed tracing to help you monitor agent behavior in development and production.

## Debug Logging

Toggle verbose logging during a session with `/debug`. Logs are written to daily files in `~/.glue/logs/`.

::: tip
Debug logging is useful for inspecting the full prompt assembly, tool calls, and token usage within a session.
:::

## OpenTelemetry (OTLP)

Export spans to any OTLP-compatible backend. Compatible with Grafana Tempo, Jaeger, Helicone, Opik, and LLMFlow.

```yaml
telemetry:
  otel:
    enabled: true
    endpoint: "https://otel.example.com/v1/traces"
    headers:
      Authorization: "Bearer ..."
```

::: info
Any backend that accepts OTLP over HTTP can be used as an endpoint, including self-hosted collectors.
:::

## Langfuse

Native Langfuse integration for LLM observability. Glue emits generation and span events with token usage, latency, and error tracking.

```yaml
telemetry:
  langfuse:
    enabled: true
    base_url: "https://cloud.langfuse.com"
    public_key: "pk-..."
    secret_key: "sk-..."
```

::: warning
Keep your Langfuse secret key out of version control. Use environment variables or a local override file for sensitive credentials.
:::

## See also

- [ObservabilityConfig](/api/observability/observability-config)
- [OtelSink](/api/observability/otel-sink)
- [LangfuseSink](/api/observability/langfuse-sink)
- [DebugController](/api/observability/debug-controller)
- [FileSink](/api/observability/file-sink)
