# Gemini Provider Implementation Plan

Status: ready to execute
Date: 2026-04-25
Branch: `refactor/c1-turn`
Supersedes: `docs/plans/2026-04-21-gemini-provider-auth-plan.md` (pre-refactor)

## Context

The earlier plan was written before the `bin → boot → runtime → {agent,tools,session,providers}` refactor and spent most of its effort weighing Google-login / Code Assist / Vertex auth. We are deliberately scoping that out: Phase 1 ships **native Gemini Developer API** support with `GEMINI_API_KEY`. Google-login OAuth (`gemini-code-assist`) and Vertex remain explicitly out of scope.

The catalog already declares the `gemini` provider (`adapter: gemini`, `auth: env:GEMINI_API_KEY`) but **no Dart adapter exists yet**, so any user trying to select a Gemini model today hits "no adapter registered for wire protocol gemini". This plan implements that adapter and refreshes the catalog with the current Gemini 3.x / 2.5 lineup plus the Deep Research agents.

## Goal

1. Implement a native `GeminiProvider` (adapter + `LlmClient` in one class) that talks to the Gemini Developer API streaming endpoint and slots into the existing provider/registry/factory machinery used by Anthropic and OpenAI.
2. Refresh `docs/reference/models.yaml` with the current Gemini chat models (replacing the placeholder `gemini-pro-latest` / `gemini-flash-latest` aliases) and register the Deep Research agents as experimental entries.
3. Provide a clear contract for a follow-up Deep Research agent runner without implementing it now — the agent surface needs background polling, not synchronous streaming, so it does not fit `LlmClient` and is deferred.

Non-goals:

- Google-account OAuth / Code Assist (`gemini-code-assist` provider)
- Vertex AI provider
- Lyria audio models
- Image-generation / TTS preview models (different APIs)
- A working Deep Research execution path (catalog entries only; runtime support is Phase 2)

## Architecture Fit

The current architecture (verified by exploration) makes this a focused, well-bounded change:

- `ProviderAdapter` interface lives at `cli/lib/src/providers/provider_adapter.dart:27-91`. The default `beginInteractiveAuth` already handles `AuthKind.apiKey` via `ApiKeyFlow`, so no override is needed.
- `AdapterRegistry` is wired in `cli/lib/src/boot/providers.dart:9-23`. Adding `GeminiProvider(...)` to that list is the only wiring change.
- `LlmClient` contract is `Stream<LlmChunk> stream(messages, {tools})` — `cli/lib/src/llm/llm.dart:60-68`. Chunks normalize to `TextDelta`, `ToolCallStart`, `ToolCallComplete`, `UsageInfo`.
- SSE parsing exists in `cli/lib/src/llm/sse.dart` (used by Anthropic + OpenAI). Gemini's `streamGenerateContent?alt=sse` endpoint returns SSE, so we reuse `decodeSse`.
- Message mapping lives in `cli/lib/src/llm/message_mapper.dart`. Gemini's wire format (parts/role=user|model, separate `systemInstruction`, `functionCall` / `functionResponse` parts) differs enough from both Anthropic and OpenAI that we add a third mapper rather than try to share.
- Tool schema encoding lives in `cli/lib/src/llm/tool_schema.dart`. Gemini wraps declarations as `{functionDeclarations: [...]}` so a small dedicated encoder is cleanest.

The pattern to follow is **`AnthropicProvider`** (`cli/lib/src/providers/anthropic_provider.dart`) — same dual-role shape, same per-request HTTP client lifecycle, same static `parseStreamEvents` for testability.

## Files To Create / Modify

### New
- `cli/lib/src/providers/gemini_provider.dart` — adapter + LlmClient (mirrors AnthropicProvider structure).
- `cli/test/providers/gemini_provider_test.dart` — adapter validation, message-mapping golden tests, SSE event parsing.
- `cli/test/llm/gemini_message_mapper_test.dart` — round-trip mapper tests.

### Modified
- `cli/lib/src/llm/message_mapper.dart` — add `GeminiMessageMapper`.
- `cli/lib/src/llm/tool_schema.dart` — add `GeminiToolEncoder`.
- `cli/lib/src/boot/providers.dart` — register `GeminiProvider` in `AdapterRegistry`.
- `docs/reference/models.yaml` — refresh `providers.gemini.models` (see Catalog Updates below).
- `cli/lib/src/catalog/models_generated.dart` — regenerated via `just gen` (do not edit by hand).
- `cli/lib/glue.dart` — export `GeminiProvider` if other adapters are exported there (verify pattern).

## Catalog Updates

Replace the current two placeholder entries (`gemini-pro-latest`, `gemini-flash-latest`) under `providers.gemini.models` in `docs/reference/models.yaml` with the explicit list. Keep Lyria out (image/audio, separate API). Deep Research agents are added as catalog entries with `enabled: false` and a `notes:` flag explaining the runtime gap, so the picker doesn't surface them yet but the catalog records them.

### Chat models (text/tool-using)

```yaml
gemini-3.1-pro-preview:
  name: Gemini 3.1 Pro Preview
  recommended: true
  default: true
  capabilities: [chat, tools, vision, files, json, reasoning, coding]
  context_window: 1000000
  speed: standard
  cost: medium
  notes: Current Pro-class preview. Strongest Gemini model for complex reasoning, coding, research.

gemini-3-flash-preview:
  name: Gemini 3 Flash Preview
  recommended: true
  capabilities: [chat, tools, vision, files, json, coding]
  context_window: 1000000
  speed: fast
  cost: low
  notes: Fast, balanced, multimodal. ~78% SWE-bench Verified — strong agentic-coding candidate.

gemini-3.1-flash-lite-preview:
  name: Gemini 3.1 Flash-Lite Preview
  recommended: false
  capabilities: [chat, tools, vision, json, coding]
  context_window: 1000000
  speed: fast
  cost: low
  notes: Cost-efficient, fastest performance for high-frequency, lightweight tasks.

gemini-2.5-pro:
  name: Gemini 2.5 Pro
  recommended: false
  capabilities: [chat, tools, vision, files, json, reasoning, coding]
  context_window: 1000000
  speed: standard
  cost: medium
  notes: GA model. Retires 2026-06-17. Pinned for users with stable workflows; prefer 3.1 Pro for new work.

gemini-2.5-flash:
  name: Gemini 2.5 Flash
  recommended: false
  capabilities: [chat, tools, vision, files, json, coding]
  context_window: 1000000
  speed: fast
  cost: low
  notes: GA Flash. Retires 2026-06-17. Prefer 3 Flash Preview for new work.

gemini-2.5-flash-lite:
  name: Gemini 2.5 Flash-Lite
  recommended: false
  capabilities: [chat, tools, vision, json, coding]
  context_window: 1000000
  speed: fast
  cost: low
  notes: GA Flash-Lite. Retires 2026-06-17.
```

### Deep Research agents (catalog-only, not yet runnable)

These are **agents**, not chat models. They run via the Gemini Interactions API in `background=true` mode and require polling — not the streaming chat shape `LlmClient` provides. We register them in the catalog so users can see them and the model picker has a stable id, but mark them disabled until the runtime can route them.

```yaml
deep-research-pro-preview-12-2025:
  name: Deep Research Pro (Dec 2025)
  recommended: false
  enabled: false
  capabilities: [chat, reasoning, tools]
  context_window: 1000000
  speed: slower
  cost: high
  notes: Deep Research agent (legacy preview). Requires background-execution runner — not yet wired up in Glue.

deep-research-preview-04-2026:
  name: Deep Research Preview (Apr 2026)
  recommended: false
  enabled: false
  capabilities: [chat, reasoning, tools, browser]
  context_window: 1000000
  speed: slower
  cost: high
  notes: Fast Deep Research agent — interactive use. Requires background runner (Phase 2).

deep-research-max-preview-04-2026:
  name: Deep Research Max Preview (Apr 2026)
  recommended: false
  enabled: false
  capabilities: [chat, reasoning, tools, browser]
  context_window: 1000000
  speed: slower
  cost: high
  notes: Maximum-comprehensiveness Deep Research agent. Requires background runner (Phase 2).
```

Note: `ModelDef` may not currently have a per-model `enabled` field — verify `cli/lib/src/catalog/model_catalog.dart`. If not, add one (small, schema-additive change in `catalog_parser.dart`) **or** drop the disabled entries and gate via the `notes:` text + a hard-coded skip in the picker; pick the additive route since it's clean.

Also bump `updated_at: 2026-04-25` and consider promoting `defaults.small_model` candidates if appropriate (do not change defaults in this PR — keep scope tight).

## Adapter Implementation

`cli/lib/src/providers/gemini_provider.dart`, modeled on `AnthropicProvider`:

```dart
class GeminiProvider extends ProviderAdapter implements LlmClient {
  GeminiProvider({
    this.apiKey = '',
    this.model = '',
    this.systemPrompt = '',
    String baseUrl = _defaultBaseUrl,
    http.Client Function()? requestClientFactory,
  });

  static const _defaultBaseUrl = 'https://generativelanguage.googleapis.com';
  static const _apiVersion = 'v1beta';

  @override String get adapterId => 'gemini';
  @override ProviderHealth validate(ResolvedProvider p) =>
      (p.apiKey?.isNotEmpty ?? false) ? ProviderHealth.ok : ProviderHealth.missingCredential;
  @override LlmClient createClient(...) => GeminiProvider(...);
  @override Stream<LlmChunk> stream(messages, {tools}) async* { ... }
  static Stream<LlmChunk> parseStreamEvents(Stream<Map<String, dynamic>> events) async* { ... }
}
```

### Endpoint

`POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse`

Auth header: `x-goog-api-key: {apiKey}` (preferred over `?key=` query param — keeps the key out of access logs).

### Request body shape

```json
{
  "systemInstruction": { "parts": [{ "text": "<system>" }] },
  "contents": [
    { "role": "user",  "parts": [{ "text": "..." }] },
    { "role": "model", "parts": [{ "text": "..." }, { "functionCall": { "name": "x", "args": {} } }] },
    { "role": "user",  "parts": [{ "functionResponse": { "name": "x", "response": { "content": "..." } } }] }
  ],
  "tools": [{ "functionDeclarations": [{ "name": "...", "description": "...", "parameters": { ... } }] }],
  "generationConfig": { "maxOutputTokens": 8192 }
}
```

### Response (SSE) shape

Each SSE `data:` line is a JSON object:

```json
{
  "candidates": [{
    "content": { "role": "model", "parts": [{ "text": "..." } | { "functionCall": {...} }] },
    "finishReason": "STOP" | "MAX_TOKENS" | ...
  }],
  "usageMetadata": { "promptTokenCount": N, "candidatesTokenCount": M, "totalTokenCount": N+M }
}
```

Parser (in `parseStreamEvents`):
- Iterate parts of each candidate.
- `text` → emit `TextDelta(text)`.
- `functionCall` → emit `ToolCallStart(id, name)` then `ToolCallComplete(ToolCall(id, name, args))`. Gemini does **not** stream partial JSON; each call arrives whole, so synthesize a stable id (`'gemini-call-${counter}'`) since the API doesn't supply one.
- `usageMetadata` on the final chunk → emit `UsageInfo(inputTokens: promptTokenCount, outputTokens: candidatesTokenCount)`.

## Message Mapper

`GeminiMessageMapper` in `cli/lib/src/llm/message_mapper.dart`:

- System prompt → `MappedMessages.systemPrompt` (carried separately like Anthropic).
- `Role.user` text → `{role: 'user', parts: [{text}]}`.
- `Role.assistant` with `text` and/or `toolCalls` → `{role: 'model', parts: [{text}?, {functionCall: {name, args}}*]}`.
- `Role.toolResult` → `{role: 'user', parts: [{functionResponse: {name: toolName, response: {content: text}}}]}`.
- Multimodal `ImagePart` → `{inlineData: {mimeType, data: base64}}` parts.
- Drop orphaned `toolResult` blocks (no matching prior `functionCall`) — Gemini rejects them just as Anthropic does.
- Coalesce consecutive same-role messages into one (Gemini requires alternating user/model).

The request body builder reads `MappedMessages.systemPrompt` into the top-level `systemInstruction` field.

## Tool Encoder

`GeminiToolEncoder` in `cli/lib/src/llm/tool_schema.dart`:

```dart
List<Map<String, dynamic>> encodeAll(List<Tool> tools) => [{
  'functionDeclarations': tools.map((t) => {
    'name': t.name,
    'description': t.description,
    'parameters': {
      'type': 'OBJECT',
      'properties': { for (final p in t.parameters) p.name: p.toSchema() },
      'required': [for (final p in t.parameters) if (p.required) p.name],
    },
  }).toList(),
}];
```

Note: Gemini wants `type` values in **uppercase** (`OBJECT`, `STRING`, `ARRAY`). The existing `Parameter.toSchema()` likely emits lowercase JSON Schema. Either:
- Walk and uppercase `type` in the encoder (simpler), or
- Use Gemini's lowercase tolerance if available — verify against the API.

Pick the walk-and-uppercase path; it's local and obvious.

## Wiring

In `cli/lib/src/boot/providers.dart`, add to the `AdapterRegistry([...])`:

```dart
GeminiProvider(requestClientFactory: () => httpClient('llm.gemini')),
```

No other wiring is needed — `LlmClientFactory.createFor` already looks up by `provider.adapter` via the registry.

## Tests

Mirror the patterns in `cli/test/providers/anthropic_provider_test.dart` and `cli/test/llm/message_mapper_test.dart`:

1. **Adapter health**: `validate()` returns `missingCredential` when apiKey empty, `ok` otherwise.
2. **Message mapper**:
   - User text → user/parts/text.
   - Assistant tool call → model/functionCall.
   - Tool result → user/functionResponse with matching name.
   - Orphaned tool_result is dropped.
   - Consecutive user messages coalesce.
   - Image parts → inlineData with base64 + mimeType.
3. **Tool encoder**: Tool with mixed required/optional params → correct `functionDeclarations` shape with uppercase types and `required` array.
4. **Stream parser** (`parseStreamEvents`):
   - Text deltas across multiple SSE chunks → joined `TextDelta`s.
   - `functionCall` part → emits `ToolCallStart` + `ToolCallComplete` with stable id.
   - Final chunk with `usageMetadata` → `UsageInfo`.
5. **End-to-end** (using `MockClient`): drive a full `stream()` call with a captured request body assertion (verify `x-goog-api-key`, endpoint URL, body keys).

E2E (`@Tags(['e2e'])`): one test that hits the real API behind `GEMINI_API_KEY`, gated like the existing Anthropic e2e tests.

## Verification

After implementation:

```sh
cd cli
just gen                                  # regenerate models_generated.dart
just gen-check                            # confirm clean
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test test/providers/gemini_provider_test.dart
dart test test/llm/gemini_message_mapper_test.dart
just check
```

Manual smoke test:

```sh
export GEMINI_API_KEY=...
dart run bin/glue.dart --model gemini/gemini-3-flash-preview -p "say hi in one word"
dart run bin/glue.dart --model gemini/gemini-3.1-pro-preview   # interactive, exercise tool calls (e.g. /shell)
```

Expected: streaming text appears chunk by chunk; `/model` shows the new entries; `glue doctor` reports `gemini` ok when the env var is set.

## Out of Scope (explicitly deferred)

- **Google-login / Code Assist** (`gemini-code-assist` provider). Requires real `PkceFlow` impl, loopback server, Code Assist runtime client, and warning UX. File a separate plan when there's user demand.
- **Vertex AI** (`vertex` provider). Different auth model (ADC / service-account / `GOOGLE_CLOUD_PROJECT`). Separate plan.
- **Deep Research execution.** The catalog entries above are inert until Glue grows a background-task runner for the Interactions API (`agent=...`, `background=true`, polling). That runner is a substantial separate piece of work — distinct from the synchronous streaming chat path — and should be its own plan once the chat path is shipping.
- **Lyria, image, TTS preview models.** Different endpoints / response shapes; not chat models.
- **Native Gemini Files API** (multimodal file upload). The catalog claims `files` capability for Pro models, but actual file-upload plumbing depends on Glue's `@file` flow — keep current behavior (inline `inlineData` for images is fine for now).
