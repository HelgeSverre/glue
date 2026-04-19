---
id: TASK-22.5
title: Generic OpenAI-compatible adapter with compatibility profiles
status: To Do
assignee: []
created_date: '2026-04-19 00:36'
updated_date: '2026-04-19 04:02'
labels:
  - model-provider-2026-04
  - llm
dependencies:
  - TASK-22.4
documentation:
  - cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md
parent_task_id: TASK-22
priority: high
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Groq, Ollama, OpenRouter, vLLM, LM Studio, Azure-compatible gateways should all work through one `OpenAiAdapter` with only config differences (base_url, headers, credential reference, compatibility profile).

**Compatibility profiles** (per adapter contract plan — knobs tuned per profile):
- `openai` (default) — vanilla OpenAI Chat/Responses
- `groq` — Groq's OpenAI-compatible endpoint
- `ollama` — local Ollama endpoint, `api_key: none`, no Authorization header
- `openrouter` — OpenRouter with `HTTP-Referer` / `X-Title` request headers
- `vllm` — local vLLM gateway

**Knobs each profile can tune:**
- auth header shape
- required request headers (e.g., OpenRouter)
- base path normalization
- whether `/models` endpoint exists
- whether streaming tool-call deltas are reliable
- whether arguments stream as partial JSON
- whether image input is accepted in chat messages
- whether tool results can contain images
- error response parser
- model ID prefix handling

**Files:**
- Modify: `cli/lib/src/llm/adapters/openai_adapter.dart` (from MP4)
- Create: `cli/lib/src/llm/adapters/compatibility/{openai,groq,ollama,openrouter,vllm}_profile.dart` — each is a small struct of knob values
- Integration tests with dummy servers covering: custom base URL, missing key, `none` key, custom headers, OpenRouter headers, Ollama no-auth

**Depends on:** MP4.

**Gotchas:** Some endpoints don't support `stream_options` or tool-choice modes. Fix the common 90%; document known gaps in catalog `notes:` field per model.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 User can add `providers.groq: { adapter: openai, compatibility: groq, base_url: ..., auth: { api_key: env:GROQ_API_KEY } }` with no Dart code changes
- [ ] #2 `request_headers` block (e.g., OpenRouter's `HTTP-Referer`, `X-Title`) passed on every request
- [ ] #3 Ollama works with `api_key: none` (no Authorization header added)
- [ ] #4 Each compatibility profile has a dummy-server integration test
- [ ] #5 Known-gap `notes:` updated in `cli/docs/reference/models.yaml` for affected models
<!-- AC:END -->
