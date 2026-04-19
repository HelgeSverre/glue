---
id: TASK-15
title: 'Title generation: make optional and debug-only'
status: In Progress
assignee: []
created_date: '2026-04-19 00:33'
updated_date: '2026-04-19 04:02'
labels:
  - simplification-2026-04
  - config
  - llm
dependencies: []
references:
  - cli/lib/src/llm/title_generator.dart
  - cli/lib/src/app/session_runtime.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Session titles are useful, but title generation should never affect startup, shutdown, or turn completion visible behavior. Currently: fire-and-forget via `unawaited()` (good), silent exception-catching (good), but no way to disable entirely to save tokens.

**Files:**
- `cli/lib/src/llm/title_generator.dart` (~63 LOC) — stateless, already fails silently
- `cli/lib/src/app/session_runtime.dart` lines 152–192 — caller; already `unawaited()`
- `cli/lib/src/config/glue_config.dart` — already has `titleModel` field but no on/off boolean

**Target:**
- Add `GlueConfig.titleGenerationEnabled: bool` (default `true`)
- YAML key: `title_generation_enabled: false`
- Env: `GLUE_TITLE_GENERATION_ENABLED` (true/false)
- When disabled: skip LLM client creation; session title stays `null`
- Debug log on skip/failure when `--debug` (see companion JSONL schema work)
- No stderr output in non-debug mode
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New `titleGenerationEnabled` field in `GlueConfig` parsed from YAML + env
- [ ] #2 When disabled, `TitleGenerator` is not invoked — verifiable via HTTP spy
- [ ] #3 Title stays null when disabled
- [ ] #4 No stderr output on failure in non-debug mode
- [ ] #5 Debug event emitted on skip/failure when `--debug` is set
- [ ] #6 Tests cover enabled/disabled paths
- [ ] #7 `dart test` green
<!-- AC:END -->
