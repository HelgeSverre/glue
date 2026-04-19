---
id: TASK-22
title: Model/provider/credential redesign (parent)
status: In Progress
assignee: []
created_date: '2026-04-19 00:34'
updated_date: '2026-04-19 04:02'
labels:
  - model-provider-2026-04
  - parent
  - config
dependencies: []
documentation:
  - cli/docs/plans/2026-04-19-model-provider-config-redesign.md
  - cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md
  - cli/docs/reference/models.yaml
priority: high
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make model/provider selection boring and predictable. Multi-provider support stays, but no provider-API model fetching during startup; curated catalog by default; credentials separate from catalog; easy OpenAI-compatible endpoints via generic `adapter: openai` + `compatibility` profile.

**Canonical references:**
- Higher-level plan: `cli/docs/plans/2026-04-19-model-provider-config-redesign.md`
- Adapter/contract depth: `cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md`
- Catalog shape: `cli/docs/reference/models.yaml`

**Key architectural split (from adapter contract plan):**
- `adapter` = wire protocol (`anthropic` / `openai` / `gemini` / `mistral`)
- `compatibility` = provider-specific quirks profile (`openai` / `groq` / `ollama` / `openrouter` / `vllm`)
- `ModelRef.parse` splits on FIRST slash only: `groq/qwen/qwen3-coder` → provider `groq`, model `qwen/qwen3-coder`
- `CredentialRef` is a sealed class: `EnvCredential` / `StoredCredential` / `InlineCredential` / `NoCredential`
- Capabilities include: `chat`, `streaming`, `tools`, `parallel_tools`, `vision`, `files`, `json`, `reasoning`, `coding`, `local`, `browser`, `binary_tool_results`

**Out of scope (this parent):**
- Remote catalog (MP7 — optional)
- OS keychain integration
- Azure OpenAI / Bedrock / Vertex / Copilot adapters
- Cloud runtime credential integration (see Runtime Boundary group)

**Subtasks:** MP1–MP7 (catalog parser, `provider/model` ID routing, ProviderConfig+CredentialStore, adapter interface, OpenAI-compatible generic, model picker + commands, optional remote catalog).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `glue --model anthropic/claude-sonnet-4.6` works end-to-end
- [ ] #2 `glue --model groq/qwen/qwen3-coder` works with Groq configured as `adapter: openai, compatibility: groq`
- [ ] #3 Ollama works with `auth.api_key: none`
- [ ] #4 Startup does not fetch provider model lists
- [ ] #5 Model picker defaults to curated, tool-capable models with credentials available
- [ ] #6 User can add one OpenAI-compatible provider without Dart code changes
- [ ] #7 Stale old provider config does not crash (integrates with R5)
- [ ] #8 App/agent code does not `switch` on provider enum for normal requests
- [ ] #9 All subtasks MP1–MP6 complete (MP7 optional)
<!-- AC:END -->
