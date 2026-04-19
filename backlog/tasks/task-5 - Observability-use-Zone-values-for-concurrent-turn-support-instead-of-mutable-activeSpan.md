---
id: TASK-5
title: >-
  Observability: use Zone values for concurrent turn support instead of mutable
  activeSpan
status: To Do
assignee: []
created_date: '2026-04-18 23:57'
updated_date: '2026-04-19 00:43'
labels:
  - observability
  - tech-debt
  - concurrency
dependencies: []
references:
  - cli/lib/src/observability/observability.dart
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ObservabilityRecorder.activeSpan` is a mutable instance field. This forces serial turn execution — if two turns ever run concurrently (e.g., parallel subagents, background tasks, future features), they'd stomp each other's active span.

Fix: thread the current span through `Zone.current` values so each async scope carries its own active span. Callers that read `activeSpan` use `Zone.current[#glue.activeSpan]`; the recorder provides a `runWithSpan(span, fn)` helper that wraps `runZoned`.

Location: `cli/lib/src/observability/observability.dart:80-81`

This is a prerequisite for cleanly instrumenting parallel subagents (`spawn_parallel_subagents` tool) — currently they share the parent's active span field, which gives incorrect parent/child trace relationships under concurrency.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `activeSpan` no longer a mutable instance field; replaced by Zone-scoped lookup
- [ ] #2 `runWithSpan(span, fn)` helper provided for entering a span scope
- [ ] #3 All call sites updated to use the new API
- [ ] #4 Parallel subagent runs produce correct parent/child span relationships
- [ ] #5 Unit tests cover concurrent scopes not stomping each other
- [ ] #6 TODO comment at line 80 removed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Scope narrowed by 2026-04-19 planning batch. The broader 'external observability' concern is handled by task-11 (R4 removes OTEL/Langfuse/devtools). This task remains relevant ONLY if the local Observability class survives R4 and parallel subagents continue to emit spans through it (see task-14 lazy ServiceLocator + task-24 session JSONL schema). Re-evaluate priority after R4 lands; may become obsolete entirely if `FileSink` + SE redesign makes the `activeSpan` concern moot.
<!-- SECTION:NOTES:END -->
