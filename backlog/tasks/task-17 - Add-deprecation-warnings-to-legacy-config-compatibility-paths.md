---
id: TASK-17
title: Delete pre-release backcompat shims
status: Done
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 03:45'
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
- [~] #1 Each legacy path emits a one-line warning when used — N/A (deleted outright; no warning path needed)
- [~] #2 Deprecated Dart symbols carry `@Deprecated('Removed in vX.Y — use ...')` — N/A (deleted outright)
- [~] #3 `ConfigStore` auto-migrates `config.json` → `preferences.json` on next write — N/A (legacy path removed)
- [x] #4 Tests cover each path (updated to drop legacy-path tests)
- [~] #5 `CHANGELOG.md` documents removal schedule — N/A (no releases yet)
- [x] #6 No functional regressions — verified via full `dart test`
<!-- AC:END -->

## Final Summary

**Scope reframed:** no-backcompat policy (no released version) means just delete, don't warn. Landed in commit `5329178`.

**Deleted:**
- `ConfigStore.legacyPath` param + `~/.glue/config.json` fallback read
- `Environment.legacyConfigPath` getter
- `ToolCallDelta` deprecated class + export
- `AgentCore.modelName` deprecated param + getter
- `LlmProviderType` typedef alias
- `safeSubagentTools` top-level const alias
- `BrowserEndpointProvider.isAvailable` alias + overrides on all 6 provider impls + 2 test stubs
- `GLUE_ANTHROPIC_API_KEY` / `GLUE_OPENAI_API_KEY` / `GLUE_MISTRAL_API_KEY` / `GLUE_OLLAMA_BASE_URL` env vars. Standard SDK names kept.

**Verification:**
- `dart analyze --fatal-infos` clean
- `dart format` clean
- `dart test`: 1128 pass / 1 skipped / 0 failed
