---
id: TASK-11
title: Remove OTEL/Langfuse/devtools observability
status: In Progress
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 00:45'
labels:
  - simplification-2026-04
  - removal
  - observability
dependencies:
  - TASK-12
references:
  - cli/lib/src/observability/
  - cli/lib/src/dev/devtools.dart
  - cli/lib/src/core/service_locator.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: high
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove external observability integration from the runtime path. Glue is local-first — local JSONL is enough for debugging.

**Why:** External telemetry complicates startup and service wiring, causes runtime issues when partially configured, duplicates local session/debug logs.

**Target behavior:** Write debug events to local files under `~/.glue/`; JSONL for append-only trace/event streams; JSON for config/state snapshots; no OTEL, no Langfuse, no devtools sink required for normal execution; no HTTP-client observability wrapper required for normal execution.

**Files to delete:**
- `cli/lib/src/observability/otel_sink.dart`
- `cli/lib/src/observability/langfuse_sink.dart`
- `cli/lib/src/observability/devtools_sink.dart`
- `cli/lib/src/observability/observed_llm_client.dart`
- `cli/lib/src/observability/observed_tool.dart`
- `cli/lib/src/observability/logging_http_client.dart`
- 6 test files under `cli/test/observability/` matching the above
- `cli/lib/src/dev/devtools.dart` + `cli/test/dev/devtools_test.dart` (Phase A `dart:developer` instrumentation — had no consumer once devtools sink is gone)
- Phase A instrumentation call sites scattered across: `app.dart` (`_doRender`, `_executeAndCompleteTool`), `agent_core.dart` (ReAct loop), `anthropic_client.dart`, `openai_client.dart`, `tools.dart` (per-tool Timeline), `shell_job_manager.dart`, `agent_manager.dart`

**Files to keep:**
- `cli/lib/src/observability/file_sink.dart` — local JSONL writer (future base)
- `cli/lib/src/observability/observability.dart` — `Observability` + `ObservabilitySpan` types
- `cli/lib/src/observability/debug_controller.dart` — `--debug` toggle

**Files to modify:**
- `cli/lib/src/observability/observability_config.dart` — delete `LangfuseConfig`, `OtelConfig`, `TelemetryProvider`; keep only `debug` flag
- `cli/lib/src/config/glue_config.dart` — remove `telemetry.langfuse.*`, `telemetry.otel.*` YAML parsing; remove `OTEL_EXPORTER_OTLP_*`, `LANGFUSE_*` env vars
- `cli/lib/src/core/service_locator.dart` — stop wrapping LLM client with `ObservedLlmClient`; stop wrapping tools with `ObservedTool`; use raw clients
- `cli/lib/src/agent/agent_manager.dart` — same unwrap for subagents
- `cli/lib/glue.dart` — remove external observability exports
- `cli/docs/reference/config-yaml.md` — delete telemetry section
- `cli/README.md` + `devdocs/` — remove telemetry env-var docs

**Config keys affected (all handled by R5 as deprecation warnings):** `telemetry.langfuse.*`, `telemetry.otel.*`, `telemetry.flush_interval_seconds`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `LANGFUSE_BASE_URL`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`.

**Supersedes existing tasks task-4 and task-7** — close those as Done.

**Depends on:** R5 (graceful stale-config handling) should land first so users with `telemetry:` in their config don't see errors.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `grep -r 'langfuse\|OTEL_EXPORTER\|LangfuseConfig\|OtelConfig' cli/lib cli/test` returns nothing meaningful
- [ ] #2 Glue starts with a stale `telemetry:` YAML section present (warning, not error)
- [ ] #3 LLM clients are invoked directly, no `ObservedLlmClient` wrapper
- [ ] #4 Tools are invoked directly, no `ObservedTool` wrapper
- [ ] #5 `FileSink` continues writing local spans under `~/.glue/logs/`
- [ ] #6 `--debug` still enables verbose local logging
- [ ] #7 `dart test` green, no regressions in agent/LLM paths
- [ ] #8 Close task-4 (HTTP span TTFB) with supersession note
- [ ] #9 Close task-7 (DevTools Phase B) with supersession note
<!-- AC:END -->
