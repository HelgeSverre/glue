# Prompt Caching — Research + Implementation Plan

> Status: research / design. No code changes yet.
> Re-spec'd 2026-04-30 against the harness/strategies/core split.

## Goal

Reduce per-turn LLM cost and latency for long-running Glue sessions by enabling provider-native prompt caching where available, and surface cache hit/miss data through the existing observability layer so developers can verify that caching is working.

Concretely, this plan delivers:

1. **Anthropic prompt caching** — explicit `cache_control` markers on the system prompt and on the trailing message window, with the required beta header. Parses and propagates `cache_creation_input_tokens` and `cache_read_input_tokens` from the usage response.
2. **OpenAI automatic caching** — no request-side changes needed (OpenAI caches the prompt prefix automatically for GPT-4o and newer); surfaces `cached_tokens` from `usage.prompt_tokens_details` so users can see it working.
3. **Ollama** — no caching API exists in Ollama; document as out-of-scope.
4. **Observability hookups** — extend `UsageInfo` (in `glue_core`) with cache fields; emit a per-turn `llm.completion` span via `ObservabilityHub` (in `glue_harness`) that includes cache stats alongside token counts; log cache savings where debug is enabled.

---

## How this plan relates to the harness layers

Prompt caching is a **strategies** concern — it's wire-format and per-provider — but the data it surfaces flows through the harness:

- **`glue_core`**: `UsageInfo` extension (cache token fields).
- **`glue_strategies`**: provider clients send `cache_control` markers and parse cache stats from the wire format. `MessageMapper` (`glue_strategies/lib/src/llm/message_mapper.dart`) places cache breakpoints.
- **`glue_harness`**: `AgentCore` emits the per-turn `llm.completion` span via `ObservabilityHub`. `GlueConfig` holds the opt-out flag.
- **Surfaces**: no direct work needed. CLI/ACP get the new fields automatically through `UsageInfo`; the context-inspector plan can render them later.

---

## Background

### Why prompt caching matters for Glue

Glue's agent loop re-sends the **entire conversation history** on every turn — system prompt, all prior messages, tool schemas, and tool results. In a medium-length session this can be 10–50 K tokens of repeated context per turn. Without caching, every token is billed and processed at full inference cost.

Provider-native prompt caching works by hashing a segment of the request. If the hash matches a prior request within the TTL window, the provider re-uses the KV-cache from that request rather than re-running the prefill. This can reduce cost by 80–90 % for the cached portion and halve first-token latency.

Glue's access patterns are close to ideal for caching:
- The system prompt never changes within a session.
- The tool schema list rarely changes.
- Earlier turns in the conversation are immutable.
- Only the final 1–2 turns grow on each request.

---

## Provider Reference Documentation

| Provider | Feature | URL |
|----------|---------|-----|
| Anthropic | Prompt Caching | https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching |
| Anthropic | Messages API (usage fields) | https://docs.anthropic.com/en/api/messages |
| OpenAI | Prompt Caching | https://platform.openai.com/docs/guides/prompt-caching |
| OpenAI | Chat Completions (usage object) | https://platform.openai.com/docs/api-reference/chat/object |
| Gemini | Context Caching | https://ai.google.dev/gemini-api/docs/caching (out of scope — Phase 2) |

---

## Current State Audit

### What Glue sends today

#### `AnthropicClient` (`packages/glue_strategies/lib/src/llm/anthropic_client.dart`)

- Builds a flat body with `system` (plain string) and `messages` (list of content blocks).
- Sends `anthropic-version: 2023-06-01` header.
- **No** `anthropic-beta: prompt-caching-2024-07-31` header.
- **No** `cache_control` markers anywhere in the payload.
- `parseStreamEvents` extracts `input_tokens` and `output_tokens` from the `message_start` event but does **not** read `cache_creation_input_tokens` or `cache_read_input_tokens`.

#### `OpenAiClient` (`packages/glue_strategies/lib/src/llm/openai_client.dart`)

- Sends a standard Chat Completions body.
- `parseStreamEvents` reads `usage.prompt_tokens` and `usage.completion_tokens`.
- Does **not** read `usage.prompt_tokens_details.cached_tokens`, which OpenAI includes automatically when caching occurs.

#### `UsageInfo` (`packages/glue_core/lib/src/message.dart`)

```dart
class UsageInfo extends LlmChunk {
  final int inputTokens;
  final int outputTokens;
  // ← no cache fields
}
```

#### Observability (`packages/glue_harness/lib/src/observability/`)

- `ObservabilitySpan` carries arbitrary `attributes` (`Map<String, dynamic>`).
- `AgentCore` (in `packages/glue_harness/lib/src/agent/agent_core.dart`) currently emits `agent.error` spans but no per-turn LLM completion spans.
- No existing span records token usage, so cache savings cannot be observed today.

---

## Proposed Changes

### 1. Extend `UsageInfo` with cache fields

**File:** `packages/glue_core/lib/src/message.dart`

Add two nullable `int` fields:

```dart
class UsageInfo extends LlmChunk {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadTokens;       // tokens served from cache
  final int? cacheCreationTokens;   // tokens written to cache this turn
  ...
}
```

Nullability signals "provider did not report this" rather than "zero cached tokens." Avoids misleading zeros on providers that do not support caching (Ollama).

`AgentCore.tokenCount` should continue counting only `inputTokens + outputTokens` (billable tokens on a cache miss); callers that want to show savings can compute them separately.

This is a `glue_core` change — every package picks it up automatically.

---

### 2. Anthropic prompt caching

**Files:**
- `packages/glue_strategies/lib/src/llm/anthropic_client.dart`
- `packages/glue_strategies/lib/src/llm/message_mapper.dart`

#### 2a. Add the beta header

```
anthropic-beta: prompt-caching-2024-07-31
```

Add to the static header block in `AnthropicClient.stream()`. Always safe to send; Anthropic ignores it gracefully on models that do not support caching.

#### 2b. Mark the system prompt for caching

Wrap the system prompt in a block with a cache breakpoint:

```json
"system": [
  {
    "type": "text",
    "text": "<full system prompt text>",
    "cache_control": { "type": "ephemeral" }
  }
]
```

Highest-value cache marker: system prompt never changes within a session.

#### 2c. Mark the tool schema block for caching

Top-level `cache_control` on the **last tool definition** in `tools`:

```json
"tools": [
  { "name": "...", ... },
  { "name": "...", ..., "cache_control": { "type": "ephemeral" } }
]
```

Stable across turns. Add this marker in `AnthropicClient.stream()` when `tools != null && tools.isNotEmpty`. Tool schemas come from `glue_harness`'s `ToolRegistry` via the existing `tool_schema.dart` mapper in `glue_strategies`.

#### 2d. Mark the trailing message window for caching

Anthropic allows up to **4 cache breakpoints** per request. After the system prompt and tool schema, add a `cache_control` marker on the **second-to-last user turn** so the growing conversation accumulates in cache incrementally rather than forcing a full cache-miss on every new turn.

Heuristic:
- Find the second-from-last `user`-role content block in `mapped.messages`.
- Wrap its `content` field to include `cache_control: {type: "ephemeral"}` on the last content entry in that block.

This logic belongs in `AnthropicMessageMapper.mapMessages()` in `packages/glue_strategies/lib/src/llm/message_mapper.dart`. Apply cache breakpoints as a final pass over the mapped list.

#### 2e. Parse cache usage from `message_start`

Extend the `case 'message_start':` handler in `AnthropicClient.parseStreamEvents()` to extract:

```json
"usage": {
  "input_tokens": 512,
  "cache_creation_input_tokens": 1024,
  "cache_read_input_tokens": 8192,
  "output_tokens": 0
}
```

…and include them in the `UsageInfo` chunk emitted at `message_stop`.

---

### 3. OpenAI automatic caching

**File:** `packages/glue_strategies/lib/src/llm/openai_client.dart`

OpenAI caches automatically — no request changes needed. Only work is reading the extra fields:

```json
{
  "prompt_tokens": 1024,
  "completion_tokens": 128,
  "prompt_tokens_details": { "cached_tokens": 896 }
}
```

Extend `OpenAiClient.parseStreamEvents()` to read `usage.prompt_tokens_details.cached_tokens` and populate `UsageInfo.cacheReadTokens`. There is no OpenAI equivalent of `cacheCreationTokens` — leave that null for OpenAI.

> **Note on OpenRouter:** OpenRouter proxies OpenAI-shaped completions and passes through `prompt_tokens_details`. No special handling needed.

---

### 4. Observability hookups

**Files:**
- `packages/glue_harness/lib/src/agent/agent_core.dart`
- `packages/glue_harness/lib/src/observability/observability.dart` (no changes — span infrastructure already suitable)

#### 4a. Emit an `llm.completion` span per agent turn

`AgentCore.run()` already collects `UsageInfo` chunks but does nothing with them except increment `tokenCount`. After each LLM call completes (after the `await for` loop), emit a span via `ObservabilityHub`:

```
name:  "llm.completion"
kind:  "client"
attributes:
  gen_ai.request.model:       <modelId>
  gen_ai.usage.input_tokens:  <inputTokens>
  gen_ai.usage.output_tokens: <outputTokens>
  llm.cache_read_tokens:      <cacheReadTokens | 0>
  llm.cache_creation_tokens:  <cacheCreationTokens | 0>
  llm.cache_savings_pct:      <cacheReadTokens / inputTokens * 100, 0 if unavailable>
```

Only emitted when `_obs != null`, so zero overhead when observability is off.

Attribute naming follows [OpenTelemetry GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/llm-spans/) where practical; `llm.*` prefix is used for cache-specific fields not yet in the stable OTel spec.

#### 4b. Debug log cache savings

When `Observability.debugEnabled` is true, log a one-liner after each turn:

```
[llm] turn 3 — input: 12 840 tokens  cached: 11 200 (87 %)  created: 0  output: 342
```

Helps developers confirm caching works without a full telemetry backend.

---

### 5. Config / feature flag

Prompt caching changes the wire format (new `system` block array shape, extra headers, `cache_control` fields). Edge cases:

- **Older Anthropic models** ignore `cache_control` markers — safe.
- **Non-Anthropic endpoints behind an Anthropic-shaped proxy** might reject the beta header. Expose `GLUE_ANTHROPIC_PROMPT_CACHE` (env) / `anthropic_prompt_cache: true` (config file) defaulting to `true`. Users with custom proxies can opt out.

**File:** `packages/glue_harness/lib/src/config/glue_config.dart`

---

## File Change Summary

| File | Change |
|------|--------|
| `packages/glue_core/lib/src/message.dart` | Add `cacheReadTokens` and `cacheCreationTokens` to `UsageInfo` |
| `packages/glue_strategies/lib/src/llm/anthropic_client.dart` | Add beta header; system-as-block with `cache_control`; trailing tool-schema `cache_control`; parse `cache_creation_input_tokens` / `cache_read_input_tokens` |
| `packages/glue_strategies/lib/src/llm/message_mapper.dart` | `AnthropicMessageMapper.mapMessages()`: apply `cache_control` to penultimate user-turn content block |
| `packages/glue_strategies/lib/src/llm/openai_client.dart` | Parse `usage.prompt_tokens_details.cached_tokens` into `UsageInfo.cacheReadTokens` |
| `packages/glue_harness/lib/src/agent/agent_core.dart` | Emit `llm.completion` span via `ObservabilityHub` |
| `packages/glue_harness/lib/src/config/glue_config.dart` | Add `anthropicPromptCache` bool config key (default `true`) |

**No changes needed:**
- `packages/glue_strategies/lib/src/llm/ollama_client.dart` — Ollama has no caching API.
- `packages/glue_harness/lib/src/observability/observability.dart` — span infrastructure already suitable.
- `packages/glue_strategies/lib/src/providers/` — adapter layer doesn't need to know about cache; purely a client concern.

---

## Tests to Write / Extend

| Test file | What to add |
|-----------|-------------|
| `packages/glue_strategies/test/llm/anthropic_client_test.dart` | Assert `cache_creation_input_tokens` + `cache_read_input_tokens` in `message_start` are surfaced in `UsageInfo`; assert beta header present; assert system block shape; assert trailing `cache_control` on tool schema |
| `packages/glue_strategies/test/llm/openai_client_test.dart` | Assert `prompt_tokens_details.cached_tokens` surfaces in `UsageInfo.cacheReadTokens` |
| `packages/glue_strategies/test/llm/message_mapper_test.dart` | Assert `cache_control` is placed on the penultimate user turn block when 3+ messages are present |
| `packages/glue_harness/test/agent/agent_core_test.dart` | Assert `llm.completion` span is emitted with correct attributes when `obs` is provided |
| `packages/glue_harness/test/config/glue_config_test.dart` | Assert `anthropicPromptCache` resolves from env / file / default |

---

## Non-Goals (explicit)

- **Gemini Context Caching** — completely different explicit-cache-object model; requires a dedicated provider client. Phase 2.
- **Ollama** — no server-side caching API. The Ollama runtime retains KV cache across identical prefixes in memory during a running session, but this is transparent and requires no client changes.
- **Semantic / application-level caching** (caching tool results, deduplicating repeated file reads) — out of scope.
- **Token budget / cost estimation UI** — this plan surfaces the numbers; UI is deferred to the context-inspector plan (`2026-04-21-context-inspector-and-telemetry.md`), which already accounts for cache fields by including them in `ContextSnapshot` via `UsageInfo`.
- **Manual cache invalidation** — provider caches expire automatically (Anthropic: 5 minutes TTL for ephemeral; OpenAI: ~1 hour); no eviction API needed.

---

## Implementation Checklist

- [ ] Extend `UsageInfo` (in `glue_core`) with `cacheReadTokens` and `cacheCreationTokens` nullable ints
- [ ] Add `anthropic-beta: prompt-caching-2024-07-31` header to `AnthropicClient`
- [ ] Convert Anthropic `system` field from plain string to block array with `cache_control`
- [ ] Add trailing `cache_control` marker to last tool schema entry in `AnthropicClient`
- [ ] Update `AnthropicMessageMapper.mapMessages()` to apply `cache_control` on penultimate user turn
- [ ] Parse `cache_creation_input_tokens` / `cache_read_input_tokens` in `AnthropicClient.parseStreamEvents()`
- [ ] Parse `prompt_tokens_details.cached_tokens` in `OpenAiClient.parseStreamEvents()`
- [ ] Add `anthropicPromptCache` config key to `GlueConfig` (in `glue_harness`)
- [ ] Emit `llm.completion` span in `AgentCore.run()` with token + cache attributes via `ObservabilityHub`
- [ ] Add debug-mode cache savings log line
- [ ] Write/extend tests in the right packages (strategies for parsers + mapper, harness for span + config)
