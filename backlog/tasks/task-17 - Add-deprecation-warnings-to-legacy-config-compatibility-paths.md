---
id: TASK-17
title: Add deprecation warnings to legacy config compatibility paths
status: To Do
assignee: []
created_date: '2026-04-19 00:34'
labels:
  - simplification-2026-04
  - tech-debt
  - config
dependencies: []
references:
  - cli/lib/src/storage/config_store.dart
  - cli/lib/src/config/glue_config.dart
  - cli/lib/src/web/browser/browser_endpoint.dart
  - cli/lib/glue.dart
documentation:
  - cli/docs/plans/2026-04-19-simplification-removal-plan.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several compatibility layers exist from past renames. Mark them all with `@Deprecated()` annotations and emit warnings when legacy paths are taken. Delete in a future release.

**WARNINGS ONLY in this task — no deletions.** Set removal date in `CHANGELOG.md`.

**Legacy paths:**

1. **`ConfigStore` legacy `config.json` fallback** (`cli/lib/src/storage/config_store.dart` lines 20–26)
   - `~/.glue/preferences.json` (current) ← `~/.glue/config.json` (legacy, NAME-001)
   - Warn on legacy-path read; auto-migrate on next write

2. **API-key env-var aliases** (DUP-003, `cli/lib/src/config/glue_config.dart` lines 204–214)
   - `ANTHROPIC_API_KEY` vs `GLUE_ANTHROPIC_API_KEY` (and openai, mistral)
   - If non-`GLUE_*` set without `GLUE_*` counterpart → warn

3. **`BrowserEndpointProvider.isAvailable` alias** (NAME-003, `cli/lib/src/web/browser/browser_endpoint.dart` lines 59–60)
   - Already `@Deprecated` — add explicit removal version

4. **`ToolCallDelta` export alias** (NAME-006, `cli/lib/glue.dart`)
   - Canonical: `ToolCallComplete` — mark with `@Deprecated('Removed in vX.Y')`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each legacy path emits a one-line warning when used
- [ ] #2 Deprecated Dart symbols carry `@Deprecated('Removed in vX.Y — use ...')`
- [ ] #3 `ConfigStore` auto-migrates `config.json` → `preferences.json` on next write
- [ ] #4 Tests cover warning emission for each path
- [ ] #5 `CHANGELOG.md` documents removal schedule
- [ ] #6 No functional regressions
<!-- AC:END -->
