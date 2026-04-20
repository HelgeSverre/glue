---
id: TASK-29
title: "Friendlier Ollama errors: daemon-down + model-missing handling"
status: To Do
assignee: []
created_date: "2026-04-19 03:49"
updated_date: "2026-04-20 00:05"
labels:
  - providers
  - ux
  - ollama
milestone: m-0
dependencies: []
references:
  - cli/lib/src/llm/ollama_client.dart
  - cli/lib/src/providers/compatibility_profile.dart
  - cli/lib/src/providers/openai_compatible_adapter.dart
  - cli/lib/src/agent/agent_core.dart
  - cli/lib/src/rendering/block_renderer.dart
  - cli/lib/src/app/spinner_runtime.dart
priority: medium
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Today, when Ollama isn't running or the requested model isn't pulled, Glue surfaces raw transport exceptions — e.g. `Exception: OpenAI API error 404: {"error":{"message":"model 'devstral:latest' not found", "type":"not_found_error", ...}}`. Translate these two common failure modes into actionable, user-friendly messages at the LLM-client boundary.

Glue talks to Ollama via the OpenAI-compatible endpoint at `http://localhost:11434/v1/chat/completions` (see `cli/lib/src/llm/ollama_client.dart`), so the translation lives in the Ollama client's error path, not in the generic OpenAI client.

Scope deliberately narrow: two error modes, one provider. The generalization to other local runtimes (LM Studio, vLLM) is noted but not built.

## Phase 1 (required): friendly error translation

- In `OllamaClient` (or the OpenAI-compatible client when `CompatibilityProfile.ollama` is active), detect:
  - **Connection refused / socket errors** at `localhost:11434` → "Ollama isn't running. Start it with `ollama serve` (or `brew services start ollama`) and retry."
  - **HTTP 404 with body matching `model '<name>' not found`** → "Model `<name>` isn't installed. Install it with `ollama pull <name>`, then retry."
- Preserve the underlying error (keep in a `cause` field or equivalent) so `--verbose` / logs still see raw details.
- Rendered via existing `BlockRenderer.renderError()` (`cli/lib/src/rendering/block_renderer.dart:126-134`) — no new UI primitives.

## Phase 2 (optional / stretch): on-demand install

- When the missing-model error fires in interactive mode, offer a prompt: "Install `<name>` now? [y/N]"
- On accept, stream `POST /api/pull` (Ollama's native NDJSON progress endpoint — distinct from the OpenAI-compat chat endpoint) and render progress via the existing spinner / status line (`cli/lib/src/app/spinner_runtime.dart`). On completion, retry the original request.
- Gate behind a config flag (default off) so non-interactive / CI flows aren't surprised.

## Out of scope (document, don't build)

- Generalizing to other local providers. Leave a TODO in `CompatibilityProfile` noting the pattern could lift up.
- Health-check-on-startup. Errors on first request are sufficient signal.
- Model discovery / listing enhancements (overlaps with TASK-22 work).

## Key code pointers

- `cli/lib/src/llm/ollama_client.dart:110-114` — raw exception throw site (primary edit)
- `cli/lib/src/llm/ollama_client.dart:27` — hardcoded base URL `http://localhost:11434`
- `cli/lib/src/providers/compatibility_profile.dart:9-51` — `CompatibilityProfile.ollama` variant
- `cli/lib/src/providers/openai_compatible_adapter.dart:1-45` — adapter wiring
- `cli/lib/src/agent/agent_core.dart:305-306` — exceptions wrapped as `AgentError(e)`; translate _before_ this boundary
- `cli/lib/src/app/session_runtime.dart:74-76` — print-mode stderr path
- `cli/lib/src/rendering/block_renderer.dart:126-134` — existing red ✗ error renderer
- `cli/lib/src/app/spinner_runtime.dart` — reusable for phase-2 pull progress

## Related

- TASK-22 (provider/credential redesign) is an orthogonal umbrella; this task stands alone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 Starting Glue with the Ollama daemon stopped yields a single-line, actionable message telling the user to start Ollama — no raw `Exception:` prefix, no JSON blob.
- [ ] #2 Requesting a model that isn't installed yields a single-line, actionable message naming the missing model and the exact `ollama pull <name>` command.
- [ ] #3 Raw error details remain accessible via existing `--verbose` / log paths (verified by test or manual check).
- [ ] #4 Unit tests cover both error translations in the Ollama client's error path.
- [ ] #5 No behavior change for non-Ollama providers — existing provider tests still pass.
- [ ] #6 Phase 2 is either implemented behind an off-by-default config flag OR explicitly deferred with a follow-up task noted in the finalSummary.
<!-- AC:END -->

## Definition of Done

<!-- DOD:BEGIN -->

- [ ] #1 Manual verification: run `glue` with Ollama stopped, then separately against an uninstalled model name; paste before/after messages into finalSummary.
<!-- DOD:END -->
