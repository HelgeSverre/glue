---
id: TASK-4
title: 'Observability HTTP span: measure full stream duration, not just TTFB'
status: Done
assignee: []
created_date: '2026-04-18 23:57'
updated_date: '2026-04-19 00:43'
labels:
  - observability
  - bug
  - tech-debt
dependencies: []
references:
  - cli/lib/src/observability/logging_http_client.dart
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LoggingHttpClient` currently ends the HTTP span as soon as `_inner.send()` returns — that timestamp is TTFB (time to first byte), not the full response transfer duration. For streaming endpoints (LLM SSE, NDJSON), this under-reports latency by a large margin.

Fix: wrap the response stream so the span ends when the stream is fully consumed (or errors). Keep TTFB as a separate attribute on the span so both signals are available.

Location: `cli/lib/src/observability/logging_http_client.dart:24`

Expected span attributes after fix:
- `http.ttfb_ms` — time to first byte (currently captured as total duration)
- `http.total_ms` — full transfer including stream drain
- Span end time aligns with stream completion, not first byte

No API changes — internal observability only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 HTTP span end aligns with response stream completion, not TTFB
- [ ] #2 Both `ttfb_ms` and `total_ms` recorded as span attributes
- [ ] #3 Behavior verified for streaming and non-streaming responses
- [ ] #4 Unit tests cover streaming case with measurable gap between TTFB and total
- [ ] #5 TODO comment at line 24 removed
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Superseded by new task-11 (Remove OTEL/Langfuse/devtools observability). The `LoggingHttpClient` this task aimed to fix is on the removal list — the TTFB vs full-transfer problem disappears when the class is deleted. Tracked via `cli/docs/plans/2026-04-19-simplification-removal-plan.md` (removal #4).
<!-- SECTION:FINAL_SUMMARY:END -->
