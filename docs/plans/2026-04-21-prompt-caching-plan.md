# Prompt Caching — Research + Implementation Plan

> Status: research / design. No code changes yet.

## Goal

Reduce per-turn LLM cost and latency for long-running Glue sessions by enabling provider-native prompt caching where available, and surface cache hit/miss data through the existing observability layer so developers can verify that caching is working.

Concretely, this plan delivers:

1. **Anthropic prompt caching** — explicit `cache_control` markers on the system prompt and on the trailing message window, with the required beta header. Parses and propagates `cache_creation_input_tokens` and `cache_read_input_tokens` from the usage response.
2. **OpenAI automatic caching** — no request-side changes needed (OpenAI caches the prompt prefix automatically for GPT-4o and newer); surfaces `cached_tokens` from `usage.prompt_tokens_details` so users can see it working.
3. **Ollama** — no caching API exists in Ollama; document as out-of-scope.
4. **Observability hookups** — extend `UsageInfo` with cache fields; emit a per-turn `llm.completion` span that includes cache stats alongside token counts; log cache savings where debug is enabled.

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

Keep these links accessible during implementation; they contain the exact field names, constraints, and response shapes expected below.

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

#### `AnthropicClient` (`cli/lib/src/llm/anthropic_client.dart`)

- Builds a flat body with `system` (plain string) and `messages` (list of content blocks).
- Sends `anthropic-version: 2023-06-01` header.
- **No** `anthropic-beta: prompt-caching-2024-07-31` header.
- **No** `cache_control` markers anywhere in the payload.
- `parseStreamEvents` extracts `input_tokens` and `output_tokens` from the `message_start` event but does **not** read `cache_creation_input_tokens` or `cache_read_input_tokens`.

#### `OpenAiClient` (`cli/lib/src/llm/openai_client.dart`)

- Sends a standard Chat Completions body.
- `parseStreamEvents` reads `usage.prompt_tokens` and `usage.completion_tokens`.
- Does **not** read `usage.prompt_tokens_details.cached_tokens`, which OpenAI includes automatically when caching occurs.

#### `UsageInfo` (`cli/lib/src/agent/agent_core.dart`, line 92)

```dart
class UsageInfo extends LlmChunk {
  final int inputTokens;
  final int outputTokens;
  // ← no cache fields
}
```

#### Observability (`cli/lib/src/observability/`)

- `ObservabilitySpan` carries arbitrary `attributes` (`Map<String, dynamic>`).
- `AgentCore` currently emits `agent.error` spans but no per-turn LLM completion spans.
- No existing span records token usage, so cache savings cannot be observed today.

---

## Proposed Changes

### 1. Extend `UsageInfo` with cache fields

**File:** `cli/lib/src/agent/agent_core.dart`

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

Nullability signals "provider did not report this" rather than "zero cached tokens." This avoids misleading zeros on providers that do not support caching (Ollama) or did not return the field.

`AgentCore.tokenCount` should continue counting only `inputTokens + outputTokens` (billable tokens on a cache miss); callers that want to show savings can compute them from the new fields separately.

---

### 2. Anthropic prompt caching

**Files:** `cli/lib/src/llm/anthropic_client.dart`, `cli/lib/src/llm/message_mapper.dart`

#### 2a. Add the beta header

```
anthropic-beta: prompt-caching-2024-07-31
```

This must be present for Anthropic to accept `cache_control` markers. Add it to the static header block in `AnthropicClient.stream()`.

> **Constraint:** The header is always safe to send; Anthropic ignores it gracefully on models that do not support caching.

#### 2b. Mark the system prompt for caching

The system prompt in Glue is a long static string built once per session. Anthropic supports a list of system blocks instead of a plain string. Wrap the system prompt in a block with a cache breakpoint:

```json
"system": [
  {
    "type": "text",
    "text": "<full system prompt text>",
    "cache_control": { "type": "ephemeral" }
  }
]
```

This is the highest-value cache marker: the system prompt never changes within a session and is always the prefix of every request.

> **API Reference:** https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching#cache-control-placement

#### 2c. Mark the tool schema block for caching

When tools are present, Anthropic accepts a top-level `cache_control` on the **last tool definition** in the `tools` array:

```json
"tools": [
  { "name": "...", "description": "...", "input_schema": {...} },
  { "name": "...", "description": "...", "input_schema": {...},
    "cache_control": { "type": "ephemeral" }   ← on the last entry only
  }
]
```

The tool list is stable across turns in a session, making this the second-best caching target. Add this marker in `AnthropicClient.stream()` when `tools != null && tools.isNotEmpty`.

#### 2d. Mark the trailing message window for caching

Anthropic allows up to **4 cache breakpoints** per request. After the system prompt and tool schema, add a `cache_control` marker on the **second-to-last user turn** (or on the last human turn if there are only two turns). This lets the growing conversation accumulate in cache incrementally rather than forcing a full cache-miss on every new turn.

The exact heuristic:
- Find the second-from-last `user`-role content block in `mapped.messages`.
- Wrap its `content` field to include `cache_control: {type: "ephemeral"}` on the last content entry in that block.

> **Constraint:** Only the last user-role message's content blocks accept `cache_control`. Applying the marker to the penultimate user turn leaves the final user input (the new prompt) uncached — which is correct, since it is different every turn.

This logic belongs in `AnthropicMessageMapper.mapMessages()` in `message_mapper.dart`. The mapper currently returns `MappedMessages`; it can apply the cache breakpoints as a final pass over the mapped list.

#### 2e. Parse cache usage from `message_start`

Anthropic returns cache statistics in the `message_start` event's `usage` block:

```json
{
  "type": "message_start",
  "message": {
    "usage": {
      "input_tokens": 512,
      "cache_creation_input_tokens": 1024,
      "cache_read_input_tokens": 8192,
      "output_tokens": 0
    }
  }
}
```

Extend the `case 'message_start':` handler in `AnthropicClient.parseStreamEvents()` to extract these fields and include them in the `UsageInfo` chunk emitted at `message_stop`.

> **Wire format reference:** https://docs.anthropic.com/en/api/messages — see the `usage` object on streaming `message_start` events.

---

### 3. OpenAI automatic caching

**File:** `cli/lib/src/llm/openai_client.dart`

OpenAI caches automatically — no request changes are needed. The only work is reading the extra fields from the usage response.

In the final usage chunk (the one emitted after all choices), the `usage` object may include:

```json
{
  "prompt_tokens": 1024,
  "completion_tokens": 128,
  "prompt_tokens_details": {
    "cached_tokens": 896
  }
}
```

Extend `OpenAiClient.parseStreamEvents()` to read `usage.prompt_tokens_details.cached_tokens` and populate `UsageInfo.cacheReadTokens`. There is no OpenAI equivalent of `cacheCreationTokens` — the cache is managed transparently; leave `cacheCreationTokens` null for OpenAI.

> **Wire format reference:** https://platform.openai.com/docs/api-reference/chat/object — see the `usage` → `prompt_tokens_details` field.

> **Note on OpenRouter:** OpenRouter proxies OpenAI-shaped completions and passes through the `prompt_tokens_details` field from the upstream provider. No special handling needed — parsing `prompt_tokens_details.cached_tokens` in `OpenAiClient` already covers OpenRouter.

---

### 4. Observability hookups

**Files:** `cli/lib/src/agent/agent_core.dart`, `cli/lib/src/observability/observability.dart`

#### 4a. Emit an `llm.completion` span per agent turn

`AgentCore.run()` already collects `UsageInfo` chunks but does nothing with them except increment `tokenCount`. After each LLM call completes (i.e., after the `await for` loop), emit a span:

```
name:  "llm.completion"
kind:  "client"
attributes:
  model:                     <modelId>
  llm.input_tokens:          <inputTokens>
  llm.output_tokens:         <outputTokens>
  llm.cache_read_tokens:     <cacheReadTokens | 0>
  llm.cache_creation_tokens: <cacheCreationTokens | 0>
  llm.cache_savings_pct:     <cacheReadTokens / inputTokens * 100, 0 if unavailable>
```

This span is only emitted when `_obs != null`, so it has zero overhead for users who haven't enabled observability.

Attribute naming follows [OpenTelemetry GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/llm-spans/) where practical (`gen_ai.usage.input_tokens`, etc.); the `llm.*` prefix is used for cache-specific fields that are not yet in the stable OTel spec.

#### 4b. Debug log cache savings

When `Observability.debugEnabled` is true, log a one-liner after each turn showing the cache hit rate:

```
[llm] turn 3 — input: 12 840 tokens  cached: 11 200 (87 %)  created: 0  output: 342
```

This helps developers confirm caching is actually working without needing a full telemetry backend.

---

### 5. Config / feature flag

Prompt caching changes the wire format (new `system` block array shape, extra headers, `cache_control` fields). Some edge cases to consider:

- **Older Anthropic model versions** do not support caching even with the beta header — they silently ignore `cache_control` markers, so this is safe.
- **Non-Anthropic endpoints behind an Anthropic-shaped proxy** might reject the beta header or the `cache_control` field. For this reason, expose a config key `GLUE_ANTHROPIC_PROMPT_CACHE` (env) / `anthropic_prompt_cache: true` (config file) that defaults to `true`. Users with custom proxies can opt out.

---

## File Change Summary

| File | Change |
|------|--------|
| `cli/lib/src/agent/agent_core.dart` | Add `cacheReadTokens` and `cacheCreationTokens` to `UsageInfo`; emit `llm.completion` span in `AgentCore.run()` |
| `cli/lib/src/llm/anthropic_client.dart` | Add beta header; system-as-block with `cache_control`; tool-schema trailing `cache_control`; parse `cache_creation_input_tokens` / `cache_read_input_tokens` |
| `cli/lib/src/llm/message_mapper.dart` | `AnthropicMessageMapper.mapMessages()`: apply `cache_control` to the penultimate user-turn content block |
| `cli/lib/src/llm/openai_client.dart` | Parse `usage.prompt_tokens_details.cached_tokens` into `UsageInfo.cacheReadTokens` |
| `cli/lib/src/config/glue_config.dart` | Add `anthropicPromptCache` bool config key (default `true`) |

**No changes needed:**
- `cli/lib/src/llm/ollama_client.dart` — Ollama has no caching API.
- `cli/lib/src/observability/observability.dart` — span infrastructure is already suitable.
- `cli/lib/src/providers/` — adapter layer doesn't need to know about cache; it's purely a client concern.

---

## Tests to Write / Extend

| Test file | What to add |
|-----------|-------------|
| `cli/test/llm/anthropic_client_test.dart` | Assert `cache_creation_input_tokens` + `cache_read_input_tokens` in `message_start` are surfaced in `UsageInfo`; assert beta header is present; assert system block shape; assert trailing `cache_control` on tool schema |
| `cli/test/llm/openai_client_test.dart` | Assert `prompt_tokens_details.cached_tokens` is surfaced in `UsageInfo.cacheReadTokens` |
| `cli/test/llm/message_mapper_test.dart` | Assert `cache_control` is placed on the penultimate user turn block in Anthropic-mapped output when 3+ messages are present |
| `cli/test/agent_core_test.dart` | Assert `llm.completion` span is emitted with correct attributes when `obs` is provided |

---

## Non-Goals (explicit)

- **Gemini Context Caching** — the Gemini API uses a completely different explicit-cache-object model (create a cache, reference it by ID); this requires a dedicated provider client and is deferred to Phase 2.
- **Ollama** — no server-side caching API exists. The Ollama runtime does retain KV cache across identical prefixes in memory during a running session, but this is transparent and requires no client changes.
- **Semantic / application-level caching** (e.g. caching tool results, deduplicating repeated file reads) — out of scope; tracked separately.
- **Token budget / cost estimation UI** — the plan surfaces the numbers; a UI for displaying them is deferred to the context-inspector plan (`2026-04-21-context-inspector-and-telemetry.md`).
- **Manual cache invalidation** — provider caches expire automatically (Anthropic: 5 minutes TTL for ephemeral; OpenAI: ~1 hour); no eviction API is needed on the client side.

---

## Implementation Checklist

- [ ] Extend `UsageInfo` with `cacheReadTokens` and `cacheCreationTokens` nullable ints
- [ ] Add `anthropic-beta: prompt-caching-2024-07-31` header to `AnthropicClient`
- [ ] Convert Anthropic `system` field from plain string to block array with `cache_control`
- [ ] Add trailing `cache_control` marker to last tool schema entry in `AnthropicClient`
- [ ] Update `AnthropicMessageMapper.mapMessages()` to apply `cache_control` on penultimate user turn
- [ ] Parse `cache_creation_input_tokens` / `cache_read_input_tokens` in `AnthropicClient.parseStreamEvents()`
- [ ] Parse `prompt_tokens_details.cached_tokens` in `OpenAiClient.parseStreamEvents()`
- [ ] Add `anthropicPromptCache` config key to `GlueConfig`
- [ ] Emit `llm.completion` span in `AgentCore.run()` with token + cache attributes
- [ ] Add debug-mode cache savings log line
- [ ] Write/extend tests for all parser changes and the new span emission
