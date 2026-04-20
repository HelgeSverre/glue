---
id: TASK-41
title: Ollama dynamic model discovery (merge /api/tags into picker)
status: To Do
assignee: []
created_date: '2026-04-20 00:09'
labels:
  - providers
  - ollama
  - ux
  - model-catalog
milestone: m-0
dependencies: []
references:
  - cli/lib/src/catalog/model_catalog.dart
  - cli/lib/src/catalog/models_generated.dart
  - cli/lib/src/providers/compatibility_profile.dart
  - cli/lib/src/providers/openai_compatible_adapter.dart
  - cli/lib/src/ui/model_panel_formatter.dart
documentation:
  - docs/plans/2026-04-20-ollama-dynamic-discovery.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When Glue talks to Ollama, the `/model` picker should reflect the user's *actual* installed models — merged with the curated catalog — instead of showing only curated rows that may or may not be pulled locally.

**Per the plan (`docs/plans/2026-04-20-ollama-dynamic-discovery.md`):**

- Pulled-but-uncatalogued models appear tagged "local only".
- Catalogued-but-not-pulled appear with visible "not pulled" marker.
- Catalogued-and-pulled appear normally.
- Ollama unreachable \u2192 fall back to bundled catalog silently. Never blocks startup or picker open.

**Implementation shape:**
- Fail-soft: 2s timeout, 30s in-memory cache.
- No schema change to `models.yaml`.
- Hook point: `CompatibilityProfile.ollama` + `OpenAiClient` extended with native `/api/tags` call.

**Adjacent Ollama footguns flagged in plan (sibling PRs, not this task's scope but should ship together):**
- `num_ctx=2048` injection \u2014 Ollama silently truncates agent loops above 2K context. #1 silent-failure across opencode / Claude Code via Ollama / Goose. Hook: `CompatibilityProfile.mutateBody` for `ollama`.
- Pre-0.17.3 version check \u2014 older Ollama versions miss critical fixes.
- `think=false` default for Qwen3 thinking variants under tool use.

**Why now:** existing `test/integration/ollama_catalog_registry_test.dart` only catches removed tags; dynamic discovery makes the picker stop lying about availability in real time.

**Out of scope:** Ollama-native chat path (still uses OpenAI-compat endpoint).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `/model` picker merges Ollama `/api/tags` with bundled catalog when Ollama is reachable.
- [ ] #2 Pulled-only models show with `local only` marker; catalogued-only with `not pulled` marker; catalogued-and-pulled with no marker.
- [ ] #3 Ollama unreachable → picker falls back to bundled catalog silently with no error toast and no startup delay.
- [ ] #4 Discovery timeout ≤ 2s; in-memory cache TTL 30s.
- [ ] #5 No `models.yaml` schema change.
- [ ] #6 Tests cover: happy path, Ollama down, partial overlap, cache hit/miss.
- [ ] #7 `num_ctx=2048` / version check / `think=false` siblings either implemented or explicitly tracked as separate follow-up tasks.
<!-- AC:END -->
