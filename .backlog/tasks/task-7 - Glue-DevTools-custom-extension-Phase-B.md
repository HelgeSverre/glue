---
id: TASK-7
title: Glue DevTools custom extension (Phase B)
status: Done
assignee: []
created_date: '2026-04-18 23:57'
updated_date: '2026-04-19 00:43'
labels:
  - feature
  - devtools
  - observability
  - flutter
dependencies: []
references:
  - cli/lib/src/dev/devtools.dart
documentation:
  - cli/docs/plans/2026-02-28-dart-devtools-integration-design.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a custom DevTools extension (Flutter web package) that visualizes Glue's runtime using the `dart:developer` instrumentation landed in Phase A. Phase A is complete — `lib/src/dev/devtools.dart` emits `glue.agentStep`, `glue.toolExec`, `glue.llmRequest`, `glue.renderMetrics` events and registers `ext.glue.*` service extensions. Phase B turns those signals into interactive panels.

**Design doc:** `cli/docs/plans/2026-02-28-dart-devtools-integration-design.md` (Phase B section)

**Panels to build:**
1. Agent Decision Tree — tree view per ReAct iteration, consuming `glue.agentStep` events; click to query `ext.glue.getConversation`
2. LLM Metrics Dashboard — TTFB/throughput/token charts from `glue.llmRequest`
3. Tool Execution Timeline — gantt chart of tool durations from `glue.toolExec`
4. State Inspector — live JSON view for each `ext.glue.*` extension with auto-refresh

**Package location:** `glue_devtools_extension/` (sibling of `cli/`) — Flutter web app.
**Output:** compiled into `cli/extension/devtools/build/` via `devtools_extensions build_and_copy`.
**Extension discovery:** `cli/extension/devtools/config.yaml` with Glue metadata.

Requires Flutter SDK for development (not just Dart). Phase A's AOT-strip guarantee is unaffected — the extension only activates when developers run `just dev` (JIT + VM service).

Out of scope:
- Production telemetry pipeline (this is a dev-only tool)
- Retroactive event capture (events dropped before DevTools connects remain dropped)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New Flutter web package `glue_devtools_extension/` created
- [ ] #2 `cli/extension/devtools/config.yaml` registers the extension with correct metadata
- [ ] #3 Agent Decision Tree panel renders `glue.agentStep` events interactively
- [ ] #4 LLM Metrics panel charts TTFB, throughput, and token usage from `glue.llmRequest`
- [ ] #5 Tool Timeline panel shows gantt-style tool durations from `glue.toolExec`
- [ ] #6 State Inspector panel queries `ext.glue.getAgentState`/`getConfig`/`getSessionInfo`/`getToolHistory` with auto-refresh
- [ ] #7 Justfile recipe `build-devtools` compiles the extension into `cli/extension/devtools/build/`
- [ ] #8 Manual validation: `just dev` on Glue, attach DevTools, all four panels display live data
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Superseded by new task-11 (Remove OTEL/Langfuse/devtools observability). The devtools sink and Phase A `dart:developer` instrumentation (`cli/lib/src/dev/devtools.dart`) are on the removal list — Phase B has no live event source once Phase A is gone. Tracked via `cli/docs/plans/2026-04-19-simplification-removal-plan.md` (removal #4). If custom DevTools extensions become useful again, re-open against the new JSONL event schema (task-24).
<!-- SECTION:FINAL_SUMMARY:END -->
