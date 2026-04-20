---
id: TASK-39
title: Thinking tokens in the TUI (streaming reasoning traces)
status: To Do
assignee: []
created_date: "2026-04-20 00:08"
updated_date: "2026-04-20 00:32"
labels:
  - llm
  - tui
  - rendering
  - reasoning
milestone: m-0
dependencies: []
references:
  - cli/lib/src/agent/agent_core.dart
  - cli/lib/src/llm/anthropic_client.dart
  - cli/lib/src/llm/openai_client.dart
  - cli/lib/src/llm/ollama_client.dart
  - cli/lib/src/rendering/block_renderer.dart
documentation:
  - docs/plans/2026-04-19-thinking-tokens-tui.md
priority: medium
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->

Surface streaming reasoning / "thinking" traces from reasoning-capable models (Claude extended thinking, OpenAI gpt-5/o-series, DeepSeek R1 via Ollama) in the Glue TUI as a distinct, visually muted block inline with the conversation.

**Per the plan (`docs/plans/2026-04-19-thinking-tokens-tui.md`, Phase 1):**

- Add `ThinkingDelta` variant to the `LlmChunk` sealed union.
- Flow as `AgentThinkingDelta` event through `AgentCore`.
- Render in a dedicated conversation block kind using dim/italic ANSI styling.
- Provider-specific parser additions (additive, no breakage):
  - Anthropic: `content_block_start`/`content_block_delta` with `thinking` / `thinking_delta`
  - OpenAI: `delta.reasoning` and `delta.reasoning_content` fallbacks
  - Ollama: `message.thinking`
- Round-trip thinking metadata into conversation store so resume shows it.
- Runtime toggle to hide/show thinking (keybinding + config).

**Phase 2 (out of scope):**

- Enabling thinking on providers that require opt-in (Anthropic `thinking: {budget_tokens}`, OpenAI `reasoning_effort`).
- Redacted-thinking handling for Anthropic (signed/encrypted blocks).
- Thinking token counting in `UsageInfo` (separate billing concern).
- ACP/WebUI surfaces — kept out so TASK-6.x can mirror later.

**Why now:** Catalog already tags reasoning-capable models with the `reasoning` capability, so the UX gap is visible. Provider parsers currently silently drop thinking deltas at three sites.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->

- [ ] #1 `ThinkingDelta` added to `LlmChunk`; `AgentThinkingDelta` added to `AgentEvent`.
- [ ] #2 Anthropic parser surfaces `thinking_delta`; OpenAI parser surfaces `delta.reasoning` / `delta.reasoning_content`; Ollama parser surfaces `message.thinking`.
- [ ] #3 Block renderer shows thinking dim/italic, distinct from final answer.
- [ ] #4 Block ordering preserved: thinking → (optional) tool calls → final text → next round.
- [ ] #5 Models that don't emit thinking incur zero new overhead (parsers skip unknown fields).
- [ ] #6 Runtime toggle (config + keybinding) hides/shows the thinking block.
- [ ] #7 Session resume renders historical thinking blocks.
- [ ] #8 Tests cover each provider's thinking parse path + agent event flow.
<!-- AC:END -->
