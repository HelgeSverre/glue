---
id: TASK-12
title: Graceful handling of stale config keys
status: Won't Do
assignee: []
created_date: '2026-04-19 00:28'
updated_date: '2026-04-19 03:45'
labels:
  - simplification-2026-04
  - config
  - compatibility
  - cancelled
dependencies: []
references:
  - cli/lib/src/config/glue_config.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Users' existing `~/.glue/config.yaml` may contain keys removed by R1 (`interaction_mode`, `approval_mode`) and R4 (`telemetry.*`). Glue must not crash — it must load, warn once per retired key, and continue.

**Why:** Removing config keys without a warning path breaks every user who upgrades. This task lands first so R1/R4 are non-breaking.

**Current pattern:** unknown keys are silently ignored via null-safe lookups in `GlueConfig.load()` (`(fileConfig?['key'] as Map?)?['subkey']`). No warning mechanism exists today.

**Target behavior:** introduce a lightweight deprecation-notice collector. Load-time scan for known-retired keys, print a one-line warning to stderr (dedupe per key per process), continue loading.

**Retired keys to warn on:**
- YAML: `interaction_mode`, `approval_mode`, `telemetry.*` (any key under `telemetry:`)
- Env: `GLUE_INTERACTION_MODE`, `GLUE_APPROVAL_MODE`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `LANGFUSE_BASE_URL`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`

Warning text should: name the key, say it was removed, and suggest an action ("remove this line from ~/.glue/config.yaml").

**Files to modify:**
- `cli/lib/src/config/glue_config.dart` — add retired-key scanner in `GlueConfig.load()`
- `cli/test/config/glue_config_test.dart` — add test per retired key: load succeeds, warning emitted

**Not in scope:** changing behavior for unknown keys in general; suppress-warnings flag (add only if user asks).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Startup succeeds when `config.yaml` contains `interaction_mode: ask` — warning emitted, no crash
- [ ] #2 Startup succeeds when `config.yaml` contains a full `telemetry:` section — warning emitted, no crash
- [ ] #3 Startup succeeds when env `LANGFUSE_BASE_URL` is set — warning emitted
- [ ] #4 Exactly one warning per key per process (dedupe works)
- [ ] #5 Tests cover each retired key (YAML + env)
- [ ] #6 `dart test test/config/` green
<!-- AC:END -->

## Final Summary

**Cancelled — no backwards-compatibility policy.** Glue has no released
version, so there are no user configs in the wild to preserve. Retired keys
(`interaction_mode`, `approval_mode`, `telemetry.*`, `LANGFUSE_*`,
`OTEL_EXPORTER_OTLP_*`) are silently ignored by `GlueConfig.load()`'s
existing null-safe lookups, which is adequate for development. No warning
infrastructure required.

If a released version ever lands and we need to migrate real user configs,
re-open this task then.
