---
id: TASK-22.9
title: Catalog refresh + api_id / catalog-key split
status: Done
assignee: []
created_date: '2026-04-20 00:00'
updated_date: '2026-04-20 00:00'
labels:
  - model-provider-2026-04
  - config
  - catalog
dependencies: []
documentation:
  - docs/reference/models.yaml
parent_task_id: TASK-22
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Refresh the bundled model catalog against live provider availability (April 2026)
and decouple the stable catalog key from the mutable upstream identifier.

### Catalog curation

- **Mistral**: dropped `codestral-latest` (FIM lineage, narrates instead of
  calling tools — verified in session log `1776625087046-ro`). Added
  `devstral-latest` (new default), `mistral-medium-latest`. Kept
  `mistral-large-latest`, `mistral-small-latest`.
- **Ollama**: swapped default to `qwen3-coder:30b` (community consensus,
  256K context, dedicated tool-call parser). Recommended tier: `qwen3-coder:30b`,
  `qwen3.6:35b`, `gemma4:26b`, `devstral-small-2:24b`, `qwen2.5-coder:32b`,
  `qwen3:8b`. Discoverability tier (`recommended: false`) for six popular
  non-agentic families (`mistral:7b`, `gemma3:12b`, `codellama:13b`,
  `codegemma:7b`, `starcoder2:15b`, `deepseek-coder:33b`) with notes
  explaining why they're not suitable for tool loops. Dropped `llama3.2:latest`.
- **Groq**: removed `qwen/qwen3-coder` (no longer served by Groq — would 404).
  New default `openai/gpt-oss-120b` (reasoning + coding), plus `gpt-oss-20b`,
  `llama-3.3-70b-versatile`, `llama-3.1-8b-instant` (unrecommended).

### api_id / catalog-key split

Added optional `api_id` field to model entries. When omitted, defaults to the
YAML key (zero churn for simple entries). Adapters send `model.apiId` to the
upstream HTTP body; the YAML key stays as the stable, URL-safe, user-facing
identifier in configs, sessions, and the `/model` picker.

Slash-bearing keys renamed to slugs with upstream strings moved to `api_id`:
- `groq/openai/gpt-oss-120b` → key `gpt-oss-120b`, `api_id: openai/gpt-oss-120b`
- `groq/openai/gpt-oss-20b` → key `gpt-oss-20b`, `api_id: openai/gpt-oss-20b`
- OpenRouter `anthropic/claude-sonnet-4-6` → `claude-sonnet-4-6`
- OpenRouter `openai/gpt-5.4-mini` → `gpt-5.4-mini`
- OpenRouter `google/gemini-flash-latest` → `gemini-flash-latest`

Motivation: upstream renames (like Groq removing Qwen3-Coder) should not
invalidate user configs. Matches precedent from OpenRouter (`id` vs
`canonical_slug`), LiteLLM (`model_name` vs `litellm_params.model`),
Continue.dev (`name` vs `model`), MLflow (alias vs version), Docker
(tag vs digest). Field names chosen via three-reviewer adversarial debate
(convention / clarity / minimalism) — `api_id` + `name` was the consensus
that survived all three biases.

### Ollama registry integration test

New test `test/integration/ollama_catalog_registry_test.dart` verifies every
Ollama catalog tag resolves via `https://registry.ollama.ai/v2/library/...`.
Opt-in via `-t ollama_registry`; skipped by default (network). Catches future
drift when upstream renames or retires tags.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Mistral catalog drops codestral; devstral-latest is default
- [x] #2 Ollama catalog uses qwen3-coder:30b default; has 4 recommended + 6 discoverability entries
- [x] #3 Groq catalog replaces removed qwen/qwen3-coder with gpt-oss-120b default
- [x] #4 `ModelDef.apiId` field added; defaults to `id` when omitted
- [x] #5 Adapters (openai_compatible, anthropic, copilot) use `model.apiId` on the wire
- [x] #6 All slash-bearing catalog keys slugified; upstream strings moved to `api_id`
- [x] #7 Parser test covers both the `api_id` override and the default-to-key path
- [x] #8 Integration test verifies all Ollama catalog tags resolve in the registry
- [x] #9 `dart analyze --fatal-infos` clean; catalog + provider + llm tests green
<!-- AC:END -->
