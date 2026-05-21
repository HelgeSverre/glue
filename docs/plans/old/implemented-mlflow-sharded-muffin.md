# Add MLflow observability block to user config

## Context

Earlier in this session we implemented MLflow tracing support in Glue
(parsed from `observability.mlflow.*` in config and from
`MLFLOW_TRACKING_URI` / `MLFLOW_EXPERIMENT_ID` env vars). The user now
wants that wired into their personal config so they don't need to export
env vars each session.

User decisions:

- Replace the Arize Phoenix OTEL block with MLflow — only one OTLP target
  can win at export time.
- Tracking URI: `http://localhost:5000`.
- Experiment id: `"0"` — MLflow's default experiment, always present on
  a fresh server. `MlflowConfig.isConfigured` in
  `cli/lib/src/observability/observability_config.dart:40` requires a
  non-empty `experimentId` for the `x-mlflow-experiment-id` header, so
  it can't be omitted.

## File to modify

- `~/.glue/config.yaml`

## Change

Remove the existing Phoenix `otel:` block and replace it with an
`mlflow:` block under `observability:`. Leave `debug`, `max_body_bytes`,
and `redact` unchanged.

Before:

```yaml
observability:
  debug: true
  max_body_bytes: 65536
  redact: true
  otel:
    enabled: true
    endpoint: https://app.phoenix.arize.com/s/helge-sverre
    headers:
      Authorization: Bearer <redacted>
    service_name: glue
    resource_attributes:
      openinference.project.name: glue
```

After:

```yaml
observability:
  debug: true
  max_body_bytes: 65536
  redact: true
  mlflow:
    enabled: true
    tracking_uri: http://localhost:5000
    experiment_id: "0"
```

`experiment_id` is quoted so the YAML parser keeps it as a string (the
config reader at `cli/lib/src/config/glue_config.dart:508` expects
`String?`).

## Verification

- `glue doctor` — the MLflow tracing row should show
  `http://localhost:5000` and experiment `0`, and the OTEL row should
  show as disabled.
- Start MLflow locally: `mlflow server --host 127.0.0.1 --port 5000`.
- Run a short Glue turn; traces should appear in the MLflow UI under the
  default experiment (id `0`). Check for GenAI semantic convention
  attributes on agent, LLM, and tool spans (added earlier in
  `cli/lib/src/agent/agent.dart:219` and
  `cli/lib/src/runtime/turn.dart:93`).
