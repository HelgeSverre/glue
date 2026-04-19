---
id: TASK-22.2
title: ModelRef parsing + provider/model ID routing
status: Done
assignee: []
created_date: '2026-04-19 00:36'
updated_date: '2026-04-19 04:02'
labels:
  - model-provider-2026-04
  - config
dependencies:
  - TASK-22.1
documentation:
  - cli/docs/plans/2026-04-19-provider-adapter-contract-plan.md
parent_task_id: TASK-22
priority: high
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace `LlmProvider` enum + raw model string with `provider_id/model_id` IDs throughout.

**CRITICAL parsing rule (from Provider Adapter Contract plan):** `ModelRef.parse` splits on the **FIRST slash only**. Example: `groq/qwen/qwen3-coder` → `providerId: "groq"`, `modelId: "qwen/qwen3-coder"`. The model ID may contain slashes (important for OpenRouter-style `anthropic/claude-sonnet-4.6`).

**Files:**
- Create: `cli/lib/src/config/model_ref.dart` — `ModelRef.parse(String)` + `ModelRef.format()`
- Modify: `cli/lib/src/config/glue_config.dart` — `GlueConfig.model` becomes `provider/model` string; add parsing helper
- Modify: `bin/glue.dart` — `--model` CLI flag accepts `provider/model`
- Modify: `cli/lib/src/llm/llm_factory.dart` — accept parsed (`ProviderConfig`, `ModelConfig`, catalog) tuple
- Create: `cli/test/config/model_ref_test.dart`

**Backward compat:** bare model input (no slash) emits deprecation warning and attempts default-provider fallback — this preserves existing user configs for one release.

**Depends on:** MP1 (catalog exists to resolve against).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `ModelRef.parse("anthropic/claude-sonnet-4.6")` → provider=anthropic, model=claude-sonnet-4.6
- [ ] #2 `ModelRef.parse("groq/qwen/qwen3-coder")` → provider=groq, model=qwen/qwen3-coder (splits on FIRST slash only)
- [ ] #3 `ModelRef.parse("openai/gpt-5.4")` succeeds
- [ ] #4 Malformed IDs (empty, no slash with bare-fallback disabled) produce clear errors
- [ ] #5 `glue --model anthropic/claude-sonnet-4.6` resolves to a working client
- [ ] #6 Bare-model input emits deprecation warning + uses default-provider fallback
- [ ] #7 Tests cover parse, format, malformed, slash-in-model-id, fallback
<!-- AC:END -->
