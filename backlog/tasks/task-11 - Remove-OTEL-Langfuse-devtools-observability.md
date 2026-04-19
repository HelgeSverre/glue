---
id: TASK-11
title: Remove OTEL/Langfuse/devtools observability
status: Done
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 01:13'
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
- [x] #1 `grep -r 'langfuse\|OTEL_EXPORTER\|LangfuseConfig\|OtelConfig' cli/lib cli/test` returns nothing meaningful
- [x] #2 Glue starts with a stale `telemetry:` YAML section present (warning, not error)
- [x] #3 LLM clients are invoked directly, no `ObservedLlmClient` wrapper
- [x] #4 Tools are invoked directly, no `ObservedTool` wrapper
- [x] #5 `FileSink` continues writing local spans under `~/.glue/logs/`
- [x] #6 `--debug` still enables verbose local logging
- [x] #7 `dart test` green, no regressions in agent/LLM paths
- [x] #8 Close task-4 (HTTP span TTFB) with supersession note
- [x] #9 Close task-7 (DevTools Phase B) with supersession note
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation Plan

### Approach
Delete external observability layer entirely. Keep `file_sink.dart`, `debug_controller.dart`, and the core `Observability` + `ObservabilitySpan` types so internal span-like tracing can continue via local JSONL. Also remove Phase A `dart:developer` instrumentation (no consumer after devtools sink goes).

**Stale-config defense (since task-12/R5 doesn't exist yet):** the existing `GlueConfig.load()` already silently ignores unknown keys via null-safe lookups — removing `telemetry.*` parsing means users with stale `telemetry:` YAML get no warning but also no crash. That's acceptable for now (matches acceptance #2 which only requires "warning, not error" — we achieve "silent, not error"). When task-12 lands later it adds explicit warnings.

### Steps

1. **Delete files** (observability + dev instrumentation)
   - `cli/lib/src/observability/{otel_sink,langfuse_sink,devtools_sink,observed_llm_client,observed_tool,logging_http_client}.dart`
   - `cli/lib/src/dev/devtools.dart`
   - `cli/lib/src/dev/` (delete directory if empty after)
   - `cli/test/observability/{otel_sink,langfuse_sink,devtools_sink,observed_llm_client,observed_tool,logging_http_client}_test.dart`
   - `cli/test/dev/devtools_test.dart`
   - `cli/test/observability/integration_test.dart` — examine; likely deletes (tests OTEL/Langfuse integration)
   - `cli/test/observability/buffer_bounds_test.dart` — keep if it tests `FileSink` bounds; delete if it tests sink buffers that are gone

2. **`observability_config.dart`** — simplify
   - Delete `LangfuseConfig`, `OtelConfig`, `TelemetryProvider`
   - `ObservabilityConfig` keeps only `debug` field

3. **`glue_config.dart`** — remove telemetry parsing
   - Delete `telemetrySection`, `langfuseSection`, `otelSection`, `flushInterval`, `langfuseConfig`, `otelEndpoint`, `otelHeaders`, `otelConfig` blocks (lines 400–445)
   - `ObservabilityConfig(debug: debug)` — drop other args
   - Remove `LANGFUSE_*`, `OTEL_EXPORTER_OTLP_*` env reads

4. **`service_locator.dart`** — unwrap
   - Delete imports: `devtools_sink.dart`, `langfuse_sink.dart`, `logging_http_client.dart`, `observed_llm_client.dart`, `observed_tool.dart`, `otel_sink.dart`
   - Remove `DevToolsSink`, `LangfuseSink`, `OtelSink` add-sink calls (lines 92–116)
   - Remove `startAutoFlush` block (lines 112–116)
   - Replace `LoggingHttpClient(inner: http.Client(), ...)` with just `http.Client()` directly (or delete `httpClient` var and pass directly)
   - Remove `ObservedLlmClient` wrap — use `rawLlm` directly
   - Remove `wrapToolsWithObservability` call — use `rawTools` directly
   - Still create `Observability(debugController: ...)` and `FileSink` — those stay
   - Drop `resourceAttrs`, `sinkError`, `_hostArch()` if only used by removed sinks (check)

5. **`agent_manager.dart`** — unwrap subagent path (same pattern as service_locator)

6. **Phase A instrumentation removal** (grep + delete call sites)
   - `bin/glue.dart` — `GlueDev` import + any `GlueDev.init()`, `Timeline.*`, `postEvent` calls
   - `cli/lib/src/app.dart` (and `app/` parts) — `Timeline.timeSync`, `GlueDev.*` in `_doRender`, `_executeAndCompleteTool`, etc.
   - `cli/lib/src/agent/agent_core.dart` — `TimelineTask`, `GlueDev.*`, `Flow` in ReAct loop
   - `cli/lib/src/llm/anthropic_client.dart` — `GlueDev.startAsync`, `postLlmRequest`
   - `cli/lib/src/llm/openai_client.dart` — same
   - `cli/lib/src/agent/tools.dart` — per-tool `Timeline.timeSync`, `GlueDev.postToolExec`
   - `cli/lib/src/shell/shell_job_manager.dart` — `GlueDev.log('shell.job', ...)`
   - `cli/lib/src/agent/agent_manager.dart` — `GlueDev.log('agent.subagent', ...)`

7. **Tests touched by unwrap**
   - `cli/test/agent/tool_trust_test.dart` — grep match probably references `ObservedTool`; update to not use wrapper
   - `cli/test/observability/observability_test.dart` — keep; still tests core `Observability` type
   - `cli/test/observability/debug_controller_test.dart` — keep
   - `cli/test/observability/file_sink_test.dart` — keep

8. **Barrel `cli/lib/glue.dart`** — remove exports:
   - `OtelSink`, `LangfuseSink`, `LoggingHttpClient`, `ObservedLlmClient`, `ObservedTool`, `wrapToolsWithObservability`, `LangfuseConfig`, `TelemetryProvider`, `GlueDev`

9. **Docs**
   - `cli/docs/reference/config-yaml.md` — delete telemetry section
   - `cli/README.md` — remove `LANGFUSE_*`, `OTEL_EXPORTER_OTLP_*` from env-var list
   - `devdocs/` — remove telemetry references

10. **Close superseded tasks**
    - `task-4` (HTTP span TTFB) — already Done
    - `task-7` (DevTools Phase B) — already Done
    (Both closed previously with supersession notes.)

11. **Quality gate**
    - `dart format --set-exit-if-changed .`
    - `dart analyze --fatal-infos`
    - `dart test`

### Risks
- Wide blast radius across ~15 files. Mitigate by grepping for each removed symbol before deleting + compile-checking incrementally.
- `http.Client()` replacement may lose request tracing. Acceptable — once R4 lands, session JSONL (SE parent) is the new trace path.
- `integration_test.dart` contents unknown. Read first; delete if coupled to removed sinks, preserve if testing core infra.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed OTel, Langfuse, DevTools, and HTTP-wrapper observability layers plus all Phase A `dart:developer` instrumentation. Local `FileSink` + `Observability` + `DebugController` retained — debug mode still writes JSONL spans to `~/.glue/logs/`.

**Files deleted (14):**
- `cli/lib/src/observability/{otel_sink,langfuse_sink,devtools_sink,observed_llm_client,observed_tool,logging_http_client}.dart`
- `cli/lib/src/dev/devtools.dart` (+ empty dir removed)
- `cli/test/observability/{otel_sink,langfuse_sink,devtools_sink,observed_llm_client,observed_tool,logging_http_client,buffer_bounds,integration}_test.dart`
- `cli/test/dev/devtools_test.dart` (+ empty dir removed)

**Files modified (major):**
- `cli/lib/src/observability/observability_config.dart` — collapsed to single `debug: bool` field
- `cli/lib/src/config/glue_config.dart` — removed ~50 lines of telemetry/OTEL/Langfuse parsing (env + YAML)
- `cli/lib/src/core/service_locator.dart` — dropped sink wiring, `ObservedLlmClient`, `wrapToolsWithObservability`, `LoggingHttpClient`, `resourceAttrs`, `sinkError`, `_hostArch` — raw `http.Client` / raw LLM / raw tools now
- `cli/lib/src/agent/agent_manager.dart` — unwrap subagent LLM client + tool list
- `cli/lib/src/agent/agent_core.dart` — removed `Timeline.startSync/finishSync` and `Flow.begin/end` calls in the ReAct loop, plus `dart:developer` import
- `cli/bin/glue.dart` — removed `GlueDev.registerExtensions`
- `cli/lib/src/app.dart` — removed `devtoolsState` method, `_openDevTools`, `_sessionState` field (dead after `devtoolsState` removal), unused `session_state.dart` import
- `cli/lib/src/app/command_helpers.dart` — dropped `_openDevToolsImpl`
- `cli/lib/src/commands/builtin_commands.dart` — removed `/devtools` slash command + `openDevTools` param
- `cli/lib/glue.dart` barrel — dropped exports for removed symbols
- `cli/test/agent/tool_trust_test.dart` — dropped `ObservedTool` tests
- `cli/test/commands/builtin_commands_test.dart` — dropped `openDevTools` arg
- `docs/reference/config-yaml.md` — removed telemetry YAML example + fields
- `docs/architecture/glossary.md` — collapsed observability section to local-only
- `docs/architecture/agent-loop-and-rendering.md` — rewrote section 15 (observability) and section 16 (approval, post task-8)
- `cli/README.md` — trimmed env var list; replaced pluggable observability section with "Debug logging" + updated the ascii tree
- `devdocs/guide/advanced/observability.md` — rewritten as local JSONL doc
- `devdocs/guide/contributing/architecture.md` — updated module table entry

**Verification:**
- `dart analyze --fatal-infos` clean
- `dart format --set-exit-if-changed .` clean
- `grep -r 'langfuse|OTEL_EXPORTER|LangfuseConfig|OtelConfig' cli/lib cli/test` returns nothing
- Full test suite: 1127 pass, 1 pre-existing docker flake (fails on main too, requires Docker daemon), 1 skipped
- All observability/* core tests pass (debug_controller, file_sink, observability)

**Stale config behavior:** existing user `config.yaml` with a `telemetry:` section loads silently — the null-safe lookups in `GlueConfig.load()` ignore the unknown key without warning. Explicit deprecation warnings are still pending in task-12 (R5). No crash regression.

Task supersedes task-4 (HTTP span TTFB — `LoggingHttpClient` deleted) and task-7 (DevTools Phase B — no consumer). Both were closed Done previously.
<!-- SECTION:FINAL_SUMMARY:END -->
