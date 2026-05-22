# OpenTelemetry Semantic-Convention Compliance — Plan

> Status: design. No code changes yet.
> Targets: OTel GenAI semconv (agent spans + attribute registry) and OTel HTTP client semconv. Backward-compatible with the current OpenInference-flavored attributes Glue already emits.

## Goal

Make Glue's emitted spans conform to two upstream OpenTelemetry semantic conventions while keeping today's OpenInference attributes alongside them:

1. **GenAI agent spans + attribute registry** — `gen_ai.*` namespace, span names like `chat {model}`, `invoke_agent {name}`, `execute_tool {name}`, and the recommended attribute set (provider, model, conversation id, finish reasons, token usage, tool definitions).
2. **HTTP client spans** — `http.request.method`, `url.full`, `server.address`, `server.port`, `http.response.status_code`, `error.type`, `http.request.resend_count`, header-per-attribute capture, and the `{METHOD} {target}` span-name format.

Concretely, this plan delivers:

- A single `SemConvAttributes` helper that maps Glue's internal names → OTel canonical keys (and keeps the existing OpenInference / `llm.*` keys dual-emitted).
- Updated `LoggingHttpClient` with the canonical HTTP attribute set and span-name format.
- Updated `AgentCore` and `AgentManager` so each LLM turn becomes a proper `chat {model}` (kind `CLIENT`) under an `invoke_agent {name}` (kind `INTERNAL`), with per-tool `execute_tool {name}` spans replacing today's `llm.tool_call.start` / `llm.tool_call.complete` events.
- Provider-resolved `gen_ai.provider.name` plumbed from `AnthropicAdapter` / `OpenAiCompatibleAdapter` / `OllamaAdapter` / `CopilotAdapter` / `GeminiProvider` through the LLM client into the chat span.
- Finish-reason propagation: a new `StreamEnd` variant on `LlmChunk` so each provider client can surface its terminal reason (`stop`, `length`, `tool_use`, `safety`, …) for `gen_ai.response.finish_reasons`.
- Span-kind mapping in `OtlpHttpTraceSink` switches from a `startsWith('http')` heuristic to an explicit table keyed by Glue's internal span-kind enum.
- An opt-in `captureMessages` flag on `OtelConfig` that enables the structured `gen_ai.input.messages` / `gen_ai.output.messages` JSON arrays (off by default — these can contain user code and secrets even after redaction).

This is **not** a rip-and-replace of the existing OpenInference attributes. Glue keeps emitting `openinference.span.kind`, `llm.model_name`, `llm.token_count.*`, `input.value`, `output.value` because Phoenix (Glue's primary today) and similar backends consume them. The new `gen_ai.*` keys are additive.

---

## How this plan relates to the harness layers

OTel emission lives entirely in the harness — surfaces never touch it directly.

- **Data types** (`glue_core`): a new `StreamEnd` variant on `LlmChunk` (in `llm_chunk.dart` or wherever the sealed class lives) so the terminal reason can travel from each provider client to `AgentCore`. No new types in `glue_core` beyond that.
- **Strategies** (`glue_strategies`): each provider client (`anthropic_client.dart`, `openai_client.dart`, `ollama_client.dart`) yields `StreamEnd(reason)` at the end of its stream. No span emission.
- **Harness** (`glue_harness`):
  - `observability/semconv.dart` (new): single source of truth for OTel attribute names, span-name builders, span-kind table, and well-known provider enum values.
  - `observability/logging_http_client.dart`: rewritten to emit canonical HTTP attributes and `{METHOD} {path}` span names.
  - `observability/otlp_http_trace_sink.dart`: span-kind table replaces the `startsWith('http')` heuristic; resource attributes get an `service.namespace=glue` so multi-service backends (Jaeger, Tempo) can group cleanly.
  - `observability/observability_config.dart`: add `captureMessages: bool` on `OtelConfig`.
  - `agent/agent_core.dart`: span tree restructured — `invoke_agent {name}` wraps each iteration; `chat {model}` is the LLM CLIENT call; each tool call becomes its own `execute_tool {name}` span (INTERNAL).
  - `agent/agent_manager.dart`: top-level subagent span renamed `invoke_workflow {task-summary}` per the spec when a subagent spawns subagents of its own.
  - Provider adapters (`providers/*.dart`): expose a `providerName` string matching the OTel well-known enum (`anthropic`, `openai`, `gcp.gemini`, `ollama` — note: `ollama` is not in the OTel enum, so it goes through unchanged and is documented as a Glue-specific extension).
- **Surfaces**: no surface-level changes. Slash commands and CLI rendering don't observe span attributes. The `glue doctor` Otel block (new) reports which conventions are currently being emitted.

---

## Scope Statement

Bring Glue's OTel trace export into compliance with the upstream OpenTelemetry GenAI and HTTP semantic conventions so that conformant backends (Jaeger, Tempo, OpenObserve, HyperDX, Langfuse, Phoenix, SigNoz, OpenLIT, Laminar) light up automatically without per-backend translation rules, while keeping the OpenInference attributes that Phoenix expects.

---

## Current State Audit

### What Glue emits today

Spans (from `agent_core.dart`, `agent_manager.dart`, `shell_job_manager.dart`, `logging_http_client.dart`, `app.dart`):

| Internal name             | Kind string         | Parent                | Notes                                  |
|---------------------------|---------------------|-----------------------|----------------------------------------|
| `agent.turn`              | `agent`             | (root, per turn)      | started by `cli/lib/src/app.dart:1833` |
| `agent.iteration`         | `agent`             | `agent.turn`          | one per LLM↔tool loop step             |
| `llm.stream`              | `llm`               | `agent.iteration`     | the streaming LLM call                 |
| `tool.<name>`             | `tool`              | `agent.iteration`     | tool execution                         |
| `tool.approval`           | `tool.approval`     | `agent.turn`          | TUI approval modal                     |
| `subagent`                | `subagent`          | parent agent          | child agent spawn                      |
| `shell.job`               | `shell.job`         | active span           | background `&` shell job               |
| `http.<spanKind>`         | `http.<spanKind>`   | active span           | every outbound HTTP request            |
| `session.*` (7 names)     | `session`           | (none)                | session-manager bookkeeping            |

Span-kind mapping in `otlp_http_trace_sink.dart:223-226`:

```dart
String _spanKind(String kind) {
  if (kind.startsWith('http')) return 'SPAN_KIND_CLIENT';
  return 'SPAN_KIND_INTERNAL';
}
```

Resource attributes: `service.name`, `service.version`, `telemetry.sdk.language=dart`, `telemetry.sdk.name=glue`, `session.id` (per-process), plus user-supplied `OTEL_RESOURCE_ATTRIBUTES`.

Attribute names in use (non-exhaustive):

```
openinference.span.kind                  (AGENT|LLM|TOOL)
llm.model_name
llm.message_count, llm.tool_count
llm.input_messages.count, llm.tools.count
llm.token_count.prompt, .completion, .total
llm.cache_read_tokens, llm.cache_creation_tokens, llm.cache_savings_pct
llm.output_messages.count, llm.output_text.length
llm.tool_call_count
input.value, output.value                (OpenInference: redacted JSON dump)
tool_call.id, tool.name
tool.input, tool.input_size, tool.output
tool.duration_ms, tool.success, tool.summary, tool.metadata
http.method                              (should be http.request.method)
http.url                                 (should be url.full)
http.status_code                         (should be http.response.status_code)
http.request_headers, http.response_headers   (single map; should be one attr per header)
http.request_body, http.response_body, http.request_body_size, http.response_body_size
http.duration_ms
error, error.type, error.message, error.stack
shell.job.id, process.command, process.background, process.exit_code
subagent.task, subagent.depth, subagent.model, subagent.index, subagent.total
```

### Gaps vs. OTel GenAI semconv

| Convention requirement                            | Glue today                              | Action                                |
|---------------------------------------------------|------------------------------------------|---------------------------------------|
| `gen_ai.operation.name` (`chat`, `invoke_agent`, `execute_tool`, `invoke_workflow`) | missing | add to every GenAI span |
| `gen_ai.provider.name` (`anthropic`, `openai`, `gcp.gemini`, …) | missing — only in span suffix | add; plumb through adapters |
| `gen_ai.request.model`                            | as `llm.model_name`                      | dual-emit                              |
| `gen_ai.response.model`                           | missing                                  | capture from provider response         |
| `gen_ai.response.id`                              | missing                                  | capture from provider response         |
| `gen_ai.response.finish_reasons`                  | missing                                  | new `StreamEnd` chunk variant          |
| `gen_ai.conversation.id`                          | only as resource `session.id`            | add per-span                           |
| `gen_ai.usage.input_tokens` / `output_tokens`     | as `llm.token_count.prompt`/`.completion`| dual-emit                              |
| `gen_ai.usage.cache_read.input_tokens` / `cache_creation.input_tokens` | as `llm.cache_read_tokens` / `llm.cache_creation_tokens` | dual-emit (canonical keys are identical-ish) |
| `gen_ai.usage.reasoning.output_tokens`            | missing                                  | capture from Anthropic / OpenAI thinking blocks where available |
| `gen_ai.input.messages` / `gen_ai.output.messages`| `input.value` / `output.value` (string)  | opt-in structured JSON (gated by `captureMessages`) |
| `gen_ai.system_instructions`                      | embedded in `input.value`                | opt-in, separate attribute             |
| `gen_ai.tool.definitions`                         | missing                                  | opt-in, attached to `chat` span        |
| `gen_ai.tool.name`, `gen_ai.tool.call.id`, `gen_ai.tool.type`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result` | as `tool.name`, `tool_call.id`, `tool.input`, `tool.output` | dual-emit |
| span name `chat {model}` (kind CLIENT)            | `llm.stream` (kind INTERNAL)             | rename + reclassify                    |
| span name `invoke_agent {name}` (kind INTERNAL)   | `agent.iteration` (kind INTERNAL)        | rename                                 |
| span name `execute_tool {name}` (kind INTERNAL, sibling of `chat`) | tool calls are **events on `llm.stream`** | split into discrete spans              |
| span name `invoke_workflow {name}` for multi-agent | `subagent` (kind INTERNAL)              | rename when depth > 0                  |

### Gaps vs. OTel HTTP semconv

| Convention requirement                            | Glue today                              | Action                                |
|---------------------------------------------------|------------------------------------------|---------------------------------------|
| `http.request.method`                             | `http.method`                            | dual-emit                              |
| `url.full`                                        | `http.url`                               | dual-emit                              |
| `server.address`, `server.port`                   | missing                                  | parse from request URI                 |
| `http.response.status_code`                       | `http.status_code`                       | dual-emit                              |
| `error.type` (well-known string, e.g. `timeout`, `connection_refused`, status code) | runtimeType class name | normalize to a small enum + keep `error.message` |
| `network.protocol.version`                        | missing                                  | derive from `package:http` if possible (HTTP/1.1 is the only thing `dart:io` returns easily) |
| `http.request.resend_count`                       | missing                                  | requires retry plumbing (Phase 4)      |
| Header-per-attribute (`http.request.header.<key>`, lowercased) | single map under `http.request_headers` | dual-emit; keep the map for the per-call HTTP debug log; add per-header keys for OTLP |
| span name `{METHOD} {low-card target}`            | `http.llm.anthropic`                     | switch to `POST /v1/messages` (path is low-cardinality for these providers) |
| span kind CLIENT                                  | already CLIENT via `startsWith('http')` heuristic | keep CLIENT, but make the mapping explicit |

### Span-kind table — what Glue should emit

After the changes:

| Internal kind enum | OTLP `SpanKind`        | Example name                |
|--------------------|------------------------|-----------------------------|
| `http`             | `SPAN_KIND_CLIENT`     | `POST /v1/messages`         |
| `chat`             | `SPAN_KIND_CLIENT`     | `chat claude-sonnet-4-6`    |
| `invokeAgent`      | `SPAN_KIND_INTERNAL`   | `invoke_agent glue`         |
| `executeTool`      | `SPAN_KIND_INTERNAL`   | `execute_tool read_file`    |
| `invokeWorkflow`   | `SPAN_KIND_INTERNAL`   | `invoke_workflow subagent`  |
| `shell`            | `SPAN_KIND_INTERNAL`   | `shell.job`                 |
| `session`          | `SPAN_KIND_INTERNAL`   | `session.create`            |
| `toolApproval`     | `SPAN_KIND_INTERNAL`   | `tool.approval`             |

---

## Backend compatibility matrix

From `/Users/helge/code/observe-llm` (the launcher's registry of self-hostable backends) and `/Users/helge/code/research-llmobservability` (the comparison reports):

| Backend         | Reads `gen_ai.*` | Reads OpenInference (`llm.*`, `openinference.span.kind`) | Reads OTel HTTP semconv | What to emit |
|-----------------|------------------|----------------------------------------------------------|-------------------------|--------------|
| Arize Phoenix   | partial (recent) | **primary schema** (OpenInference is theirs)             | yes                     | both         |
| Langfuse        | **primary**      | partial via adapter                                       | yes                     | both         |
| Jaeger / Tempo  | n/a              | n/a                                                       | **primary**             | OTel HTTP    |
| OpenObserve     | shows raw attrs  | shows raw attrs                                           | yes                     | both         |
| HyperDX         | shows raw attrs  | shows raw attrs                                           | yes                     | both         |
| SigNoz          | yes              | shows raw attrs                                           | yes                     | both         |
| OpenLIT         | **primary**      | partial                                                   | yes                     | both         |
| Laminar (lmnr)  | yes              | yes                                                       | yes                     | both         |
| Helicone        | proxy mode only — no OTLP ingest | n/a                                       | n/a                     | n/a          |
| LiteLLM proxy   | proxy mode only — no OTLP ingest | n/a                                       | n/a                     | n/a          |
| LLMFlow         | groups by resource `session.id` (already emitted) | partial                  | yes                     | both         |
| MLflow          | partial                          | partial                                  | yes                     | both         |

Conclusion: dual-emit is the only sane move. Today's OpenInference attributes stay; new `gen_ai.*` and OTel HTTP attributes are additive. The cost is a few extra KV pairs per span; the benefit is every backend in the launcher's registry renders Glue traces meaningfully without per-backend Collector transforms.

### Lessons from sibling agents (from `observe-llm/src/registry/agents/*.yaml`)

- **Gemini CLI** is the only agent shipping full GenAI semconv natively. Glue should match this bar.
- **Claude Code** emits partial GenAI under `claude_code.*` span names and a beta gate. Users complain that token counts live under `claude_code.*` rather than `gen_ai.usage.*`. Glue should not repeat that mistake — emit `gen_ai.usage.*` from day one.
- **Codex** emits its own `codex.*` event schema; the registry notes "needs an OTel Collector transform processor to surface as GenAI semconv." Glue avoids this by emitting `gen_ai.*` natively.
- **Goose** emits a goose-specific schema. Same lesson — vendor namespace is a poor substitute for shared semconv.
- **Opencode / Kilo Code** emit 200-400 spans/run via the JS NodeSDK + OTLP JSON exporter — high cardinality, but pairs cleanly with Jaeger/OpenObserve. Glue's volume is far lower (one tree per turn), so we are not at risk of high-cardinality blowups.

---

## Data model changes

### `LlmChunk.StreamEnd` (new variant)

`packages/glue_core/lib/src/llm_chunk.dart` (or wherever the sealed class lives — confirm via `grep "sealed class LlmChunk"`):

```dart
final class StreamEnd extends LlmChunk {
  final String? finishReason;   // 'stop' | 'length' | 'tool_use' | 'safety' | ...
  final String? responseId;     // provider's response/message id
  final String? responseModel;  // provider-echoed model id
  const StreamEnd({this.finishReason, this.responseId, this.responseModel});
}
```

`finishReason` strings follow the OTel `gen_ai.response.finish_reasons` enum (`stop`, `length`, `tool_calls`, `content_filter`, `error`) where the provider's value maps cleanly; raw provider values pass through otherwise (the spec allows that).

### `OtelConfig.captureMessages` (new field)

`packages/glue_harness/lib/src/observability/observability_config.dart`:

```dart
class OtelConfig {
  // ... existing fields ...
  final bool captureMessages;   // default false
  const OtelConfig({
    // ...
    this.captureMessages = false,
  });
}
```

Surfaced via `OTEL_GLUE_CAPTURE_MESSAGES=1` env var and a `[otel] capture_messages = true` block in `~/.glue/config.yaml` (config loader change is part of Phase 5).

### `SemConvAttributes` helper (new module)

`packages/glue_harness/lib/src/observability/semconv.dart` (new):

```dart
/// Single source of truth for OpenTelemetry semantic convention attribute
/// names. Glue dual-emits — every helper returns a Map containing both the
/// canonical OTel key and the existing OpenInference/legacy key so dashboards
/// that read either schema keep working.
abstract final class SemConv {
  // --- GenAI ---
  static const operationName = 'gen_ai.operation.name';
  static const providerName = 'gen_ai.provider.name';
  static const requestModel = 'gen_ai.request.model';
  static const responseModel = 'gen_ai.response.model';
  static const responseId = 'gen_ai.response.id';
  static const responseFinishReasons = 'gen_ai.response.finish_reasons';
  static const conversationId = 'gen_ai.conversation.id';
  static const usageInputTokens = 'gen_ai.usage.input_tokens';
  static const usageOutputTokens = 'gen_ai.usage.output_tokens';
  static const usageCacheReadInputTokens = 'gen_ai.usage.cache_read.input_tokens';
  static const usageCacheCreationInputTokens = 'gen_ai.usage.cache_creation.input_tokens';
  static const usageReasoningOutputTokens = 'gen_ai.usage.reasoning.output_tokens';
  static const inputMessages = 'gen_ai.input.messages';
  static const outputMessages = 'gen_ai.output.messages';
  static const systemInstructions = 'gen_ai.system_instructions';
  static const toolDefinitions = 'gen_ai.tool.definitions';
  static const toolName = 'gen_ai.tool.name';
  static const toolCallId = 'gen_ai.tool.call.id';
  static const toolType = 'gen_ai.tool.type';
  static const toolDescription = 'gen_ai.tool.description';
  static const toolCallArguments = 'gen_ai.tool.call.arguments';
  static const toolCallResult = 'gen_ai.tool.call.result';

  // --- HTTP ---
  static const httpRequestMethod = 'http.request.method';
  static const urlFull = 'url.full';
  static const serverAddress = 'server.address';
  static const serverPort = 'server.port';
  static const httpResponseStatusCode = 'http.response.status_code';
  static const errorType = 'error.type';
  static const networkProtocolVersion = 'network.protocol.version';
  static const httpRequestResendCount = 'http.request.resend_count';
  static String httpRequestHeader(String name) =>
      'http.request.header.${name.toLowerCase()}';
  static String httpResponseHeader(String name) =>
      'http.response.header.${name.toLowerCase()}';
}

/// OpAMP-style mapping from a Glue provider id → OTel well-known
/// `gen_ai.provider.name` value. Anything not in this table passes through
/// unchanged (Ollama and Copilot are documented Glue extensions).
String semconvProviderName(String glueProviderId) => switch (glueProviderId) {
  'anthropic' => 'anthropic',
  'openai' => 'openai',
  'gemini' || 'google' => 'gcp.gemini',
  'mistral' => 'mistral_ai',
  'groq' => 'groq',
  'deepseek' => 'deepseek',
  'xai' => 'x_ai',
  // Not in the OTel enum — passed through verbatim.
  'ollama' => 'ollama',
  'copilot' => 'github.copilot',
  _ => glueProviderId,
};

/// Maps an internal Glue span kind → (OTLP SpanKind enum, OTel
/// `gen_ai.operation.name`). The second value is null for non-GenAI spans.
({String otlpKind, String? operationName}) semconvSpanKind(String glueKind) =>
    switch (glueKind) {
      'chat' => (otlpKind: 'SPAN_KIND_CLIENT', operationName: 'chat'),
      'invokeAgent' => (otlpKind: 'SPAN_KIND_INTERNAL', operationName: 'invoke_agent'),
      'executeTool' => (otlpKind: 'SPAN_KIND_INTERNAL', operationName: 'execute_tool'),
      'invokeWorkflow' => (otlpKind: 'SPAN_KIND_INTERNAL', operationName: 'invoke_workflow'),
      'http' => (otlpKind: 'SPAN_KIND_CLIENT', operationName: null),
      _ => (otlpKind: 'SPAN_KIND_INTERNAL', operationName: null),
    };
```

This file is the **only** place where the OTel attribute names appear as string literals. Every call site uses `SemConv.foo`.

---

## Per-tool / per-span special cases

Documenting these now so the engineer doesn't have to rediscover them.

### Subagent spans → `invoke_workflow` when nested

`packages/glue_harness/lib/src/agent/agent_manager.dart:156` currently emits a `subagent` span for every spawn. The OTel `invoke_workflow` convention is meant for multi-agent orchestration where the top-level coordinator is itself the workflow. Mapping:

- Top-level user turn → `invoke_agent glue` (the main agent itself).
- Subagent spawn at depth ≥ 1 → `invoke_workflow subagent` (per the spec: "multi-agent orchestration").
- The subagent's own LLM calls inside it → nested `chat {model}` and `execute_tool {name}` spans, parented by the workflow.

The `spawn_parallel_subagents` tool fan-out becomes a single `invoke_workflow spawn_parallel_subagents` parent with N child `invoke_workflow subagent` spans. This is the only place where Glue's tree shape changes meaningfully.

### `tool.approval` span → keep as Glue-specific

The TUI approval modal (`cli/lib/src/app.dart:1913`) is not a GenAI tool execution — it's a human-in-the-loop gate. Keep it as a Glue-specific INTERNAL span (`glue.tool.approval`). Do not try to shoehorn it into `execute_tool`. Add `glue.approval.decision` (`yes` | `no` | `always`) and `glue.approval.duration_ms`.

### `shell.job` span → not a GenAI span

Background `&` shell jobs (`packages/glue_harness/lib/src/agent/shell_job_manager.dart:94`) are spawned by the `bash` tool but live on after the tool span ends — they have their own lifecycle. Keep `shell.job` as a Glue-specific INTERNAL span. Add `process.executable.name` (the leading word of the command, low-cardinality safe) and `process.pid` if `RunningCommandHandle` exposes it. Do not add `gen_ai.*` keys.

### MCP tool calls → still `execute_tool`

MCP tools route through the standard `Tool` interface (see `packages/glue_harness/lib/src/tools/mcp/`). They get the same `execute_tool {name}` span as built-in tools. Recommended extra attribute: `glue.tool.source = 'mcp'` and `glue.mcp.server = <server-id>` so dashboards can group them. Don't invent an `mcp.*` namespace — there is no upstream MCP semconv yet.

### Tool result span vs tool call span

Today, `AgentCore` yields `ToolCall` events from inside the LLM stream and resolves them later via `_pendingToolResults` (`agent_core.dart:192-194`). The CLI's `app.dart:2056` and `app.dart:2287` are the actual `agent.executeTool(call)` call sites. The `execute_tool` span has to start when the tool call is yielded (so timing reflects user-perceived latency including any approval delay) and end when `executeTool` resolves. Plumbing:

- `AgentCore.run` starts the `execute_tool` span when it emits `AgentToolCall`.
- The span is stashed in a new `_pendingToolSpans` map keyed by `call.id`.
- `AgentCore.executeTool` looks up the span instead of starting its own, and ends it with the result/error.
- Span parent is the `invoke_agent` iteration span, **not** the `chat` span. (Tools are siblings of `chat`, both children of `invoke_agent`.)

This is the largest structural change in the plan and worth a dedicated commit.

### Provider-specific finish reasons

| Provider   | Wire field                     | Maps to OTel finish reason     |
|------------|--------------------------------|--------------------------------|
| Anthropic  | `stop_reason: end_turn`        | `stop`                         |
| Anthropic  | `stop_reason: max_tokens`      | `length`                       |
| Anthropic  | `stop_reason: tool_use`        | `tool_calls`                   |
| Anthropic  | `stop_reason: stop_sequence`   | `stop`                         |
| OpenAI     | `finish_reason: stop`          | `stop`                         |
| OpenAI     | `finish_reason: length`        | `length`                       |
| OpenAI     | `finish_reason: tool_calls`    | `tool_calls`                   |
| OpenAI     | `finish_reason: content_filter`| `content_filter`               |
| Ollama     | `done_reason: stop`            | `stop`                         |
| Ollama     | `done_reason: length`          | `length`                       |
| Gemini     | `finishReason: STOP`           | `stop`                         |
| Gemini     | `finishReason: MAX_TOKENS`     | `length`                       |
| Gemini     | `finishReason: SAFETY`         | `content_filter`               |

Mapping table lives in `semconv.dart` next to `semconvProviderName`.

### Reasoning tokens

`gen_ai.usage.reasoning.output_tokens` is genuinely useful but provider-dependent:

- Anthropic exposes thinking-block tokens via `usage.thinking_tokens` on extended-thinking models (sometimes — verify against `packages/glue_strategies/lib/src/llm/anthropic_client.dart`).
- OpenAI reasoning models expose `usage.completion_tokens_details.reasoning_tokens`.
- Ollama / Gemini: not available.

Capture where available; omit attribute when not. Do not invent a value.

### Tool definitions attribute size

`gen_ai.tool.definitions` (opt-in) can be hundreds of KB for the full Glue tool catalog. Cap at 16 KB after JSON encoding; if over, emit `gen_ai.tool.definitions.truncated=true` and a count of dropped tools rather than the array. This keeps OTLP payloads sane.

### `input.messages` / `output.messages` redaction

When `captureMessages=true`, the messages are emitted as structured arrays per the OTel JSON schema. They still pass through `redactBody` for secret patterns. Additionally:

- Resource-link `ContentPart`s (file contents pulled in via `@file`) are emitted as `{type: 'resource_link', uri: '...', bytes: N}` — never include the bytes themselves.
- Image `ContentPart`s are emitted as `{type: 'image', mime: '...', bytes: N}` — never the base64 payload.
- Tool result content is truncated to 8 KB per message (separate cap from `maxBodyBytes` because messages can be larger than a single HTTP body).

---

## Implementation phases

### Phase 1 — `semconv.dart` + HTTP semconv (low risk, additive)

Goal: every outbound HTTP request carries canonical OTel HTTP attributes alongside the existing `http.*` legacy keys.

**Files:**
- Create: `packages/glue_harness/lib/src/observability/semconv.dart`
- Modify: `packages/glue_harness/lib/src/observability/logging_http_client.dart`
- Modify: `packages/glue_harness/lib/src/observability/otlp_http_trace_sink.dart` (span-kind table)
- Test: `packages/glue_harness/test/observability/semconv_test.dart` (new)
- Test: `cli/test/observability/logging_http_client_test.dart` (extend)
- Test: `cli/test/observability/otlp_http_trace_sink_test.dart` (extend)

Tasks (TDD, one commit per task):

1. **Failing test for `semconvProviderName`.** Assert that `'anthropic'` → `'anthropic'`, `'gemini'` → `'gcp.gemini'`, `'ollama'` → `'ollama'`, `'unknown-provider'` → `'unknown-provider'`. Run: `dart test test/observability/semconv_test.dart`. Expected: FAIL (module doesn't exist).
2. **Create `semconv.dart`** with the full `SemConv` class, `semconvProviderName`, `semconvSpanKind`. Re-run test. Expected: PASS. Commit.
3. **Failing test for `LoggingHttpClient` canonical HTTP attributes.** In `cli/test/observability/logging_http_client_test.dart`, post to a mock server and assert the captured span attributes contain `http.request.method=POST`, `url.full=...`, `server.address=...`, `server.port=...`, `http.response.status_code=200`, and the existing `http.method`/`http.url`/`http.status_code` legacy keys are still present. Run. Expected: FAIL.
4. **Update `LoggingHttpClient.send`** to populate the canonical keys (parse host+port from `request.url`; default port from scheme). Keep legacy keys. Span name becomes `'${request.method} ${request.url.path}'` (path stays low-cardinality for the LLM/search/browser endpoints Glue talks to). Re-run test. Expected: PASS. Commit.
5. **Failing test for header-per-attribute capture.** Assert that a request header `Content-Type: application/json` produces `http.request.header.content-type=application/json` on the span (alongside the existing `http.request_headers` map). Run. Expected: FAIL.
6. **Add per-header attribute emission** in `LoggingHttpClient` using `SemConv.httpRequestHeader(name)` / `httpResponseHeader(name)`. Re-use the existing `redactHeaders` helper so masked headers emit `****` as the value. Re-run test. Expected: PASS. Commit.
7. **Failing test for `error.type` normalization.** Drive a timeout (use `MockClient.streaming` with a forced `TimeoutException`); assert the span has `error.type='timeout'` (not `_TimeoutException` or whatever the runtime type is). Run. Expected: FAIL.
8. **Add `_normalizeErrorType` helper** in `LoggingHttpClient` covering: `TimeoutException → 'timeout'`, `SocketException → 'connection_refused'` (or `'dns_error'` if `osError.errorCode == 8`), `ClientException → 'protocol_error'`, default → the runtime-type class name. Re-run test. Expected: PASS. Commit.
9. **Failing test for explicit span-kind table** in `OtlpHttpTraceSink`. Build a span with internal kind `'chat'` and assert the OTLP `kind` is `SPAN_KIND_CLIENT`; with kind `'executeTool'`, assert `SPAN_KIND_INTERNAL`. Run. Expected: FAIL.
10. **Replace `_spanKind` heuristic** in `otlp_http_trace_sink.dart` with a call to `semconvSpanKind(span.kind).otlpKind`. Re-run test. Expected: PASS. Commit.
11. **Add `service.namespace=glue`** to resource attributes in `OtlpHttpTraceSink._toOtlpPayload` (helps Jaeger/Tempo grouping). Update existing resource-attribute test. Commit.

### Phase 2 — GenAI attributes on `chat` span (chat-level dual-emit)

Goal: every LLM call carries `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.conversation.id`, and `gen_ai.usage.*`. Span renamed to `chat {model}` with kind `chat`.

**Files:**
- Modify: `packages/glue_harness/lib/src/agent/agent_core.dart` (lines ~124-267)
- Modify: `packages/glue_harness/lib/src/agent/agent_runner.dart` (mirror changes if it starts its own spans — check first)
- Modify: each provider adapter (`packages/glue_harness/lib/src/providers/*.dart`) to expose `providerName`
- Modify: each LLM client (`packages/glue_strategies/lib/src/llm/*.dart`) to surface `providerName` to `AgentCore`
- Test: `packages/glue_harness/test/agent/agent_core_otel_test.dart` (new)

Tasks:

1. **Failing test:** stub an LLM client that yields a single `TextDelta('hi')` then completes. Run an `AgentCore.run('go')` through it with `obs` attached. Assert the captured `llm.stream` (or `chat`) span has `gen_ai.operation.name='chat'`, `gen_ai.provider.name='anthropic'`, `gen_ai.request.model='claude-sonnet-4-6'`, `gen_ai.conversation.id=<session id>`. Run. Expected: FAIL.
2. **Add `providerName` getter** to the `LlmClient` interface (in `packages/glue_strategies/lib/src/llm/llm_client.dart` or wherever the interface lives). Each implementation returns the OTel-canonical string via `semconvProviderName`. Each provider adapter (Anthropic/OpenAI/Ollama/Copilot/Gemini) passes its own id through. Commit.
3. **Modify `AgentCore.run`** to take an optional `conversationId` constructor arg (plumbed from `App._sessionManager.currentSessionId`). On the chat span: add `gen_ai.operation.name=chat`, `gen_ai.provider.name=llm.providerName`, `gen_ai.request.model=modelId`, `gen_ai.conversation.id=conversationId`. Keep all existing `llm.*` and `openinference.span.kind` attributes. Re-run test. Expected: PASS. Commit.
4. **Failing test for token-usage dual-emit.** Use a stub that yields a `UsageInfo` and assert the ended span has both `llm.token_count.prompt=N` and `gen_ai.usage.input_tokens=N`. Run. Expected: FAIL.
5. **Update the usage-aggregation block** at `agent_core.dart:244-265` to emit canonical keys alongside legacy ones via a helper `_usageExtras(...)` in `semconv.dart`. Re-run test. Expected: PASS. Commit.
6. **Plumb `conversationId`** from `App._startAgent` (`cli/lib/src/app.dart:1822`) and ACP delegate (`cli/lib/src/acp/cli_acp_delegate.dart`) into `AgentCore`. Add a similar arg to `AgentManager.spawnSubagent` so subagent chats inherit it. Commit.

### Phase 3 — Stream end + finish reasons + response id/model

Goal: every LLM call's `chat` span ends with `gen_ai.response.finish_reasons`, `gen_ai.response.id`, `gen_ai.response.model`.

**Files:**
- Modify: `packages/glue_core/lib/src/llm_chunk.dart` (add `StreamEnd` variant)
- Modify: `packages/glue_strategies/lib/src/llm/anthropic_client.dart` (yield `StreamEnd`)
- Modify: `packages/glue_strategies/lib/src/llm/openai_client.dart` (yield `StreamEnd`)
- Modify: `packages/glue_strategies/lib/src/llm/ollama_client.dart` (yield `StreamEnd`)
- Modify: `packages/glue_strategies/lib/src/llm/gemini_client.dart` (yield `StreamEnd` — confirm filename)
- Modify: `packages/glue_harness/lib/src/agent/agent_core.dart` (consume `StreamEnd` in the `switch (chunk)` at line ~164)
- Test: `packages/glue_strategies/test/llm/anthropic_client_test.dart` (extend), same for openai/ollama/gemini

Tasks:

1. **Failing test for Anthropic finish-reason mapping.** Feed an SSE fixture ending with `message_delta { stop_reason: 'tool_use' }`; assert the stream's last chunk is `StreamEnd(finishReason: 'tool_calls', responseId: 'msg_...', responseModel: 'claude-sonnet-4-6')`. Run. Expected: FAIL.
2. **Add `StreamEnd`** to `LlmChunk` sealed union. Re-run all existing chunk-related tests to confirm exhaustiveness checking pulls every `switch (chunk)` into compile errors. Fix each by adding a no-op or a passthrough case temporarily. Commit.
3. **Implement `StreamEnd` emission** in Anthropic client using the mapping table from "Provider-specific finish reasons" above. Re-run test. Expected: PASS. Commit.
4. **Repeat tasks 1+3** for OpenAI, Ollama, Gemini, Copilot (each as its own commit so reverting one provider is cheap).
5. **Consume `StreamEnd`** in `AgentCore.run` `switch (chunk)`. Stash `finishReason`, `responseId`, `responseModel` in locals; emit them on the chat span at end. Add `gen_ai.response.finish_reasons` as a list (single-element for now since Glue's `n=1` always). Commit.
6. **Add `gen_ai.usage.reasoning.output_tokens`** capture in the Anthropic and OpenAI clients where the wire format exposes it. Document the absence for Ollama/Gemini in a code comment in each client.

### Phase 4 — Discrete `execute_tool` spans (the structural change)

Goal: tool calls become sibling spans of `chat`, not events on it. Each is named `execute_tool {name}`, carries `gen_ai.*` tool attributes, and times from yield to result resolution.

**Files:**
- Modify: `packages/glue_harness/lib/src/agent/agent_core.dart` (heavy — the `run` loop and `executeTool`)
- Modify: `cli/lib/src/app.dart` (only if it starts its own tool span — confirm `app.dart:1913` is the approval span, not the tool span)
- Test: `packages/glue_harness/test/agent/agent_core_otel_test.dart` (extend)

Tasks:

1. **Failing test:** stub an LLM that yields `ToolCallComplete(read_file)` then completes. Register a stub `read_file` tool. Run a turn and assert: the span tree has `invoke_agent` (renamed from `agent.iteration`) with two children — `chat claude-sonnet-4-6` and `execute_tool read_file` — and the `execute_tool` span has `gen_ai.operation.name=execute_tool`, `gen_ai.tool.name=read_file`, `gen_ai.tool.call.id=<id>`, `gen_ai.tool.type=function`, and a non-zero `duration_ms`. Run. Expected: FAIL.
2. **Rename `agent.iteration` → `invoke_agent {agentName}`** with kind `invokeAgent` in `agent_core.dart:124`. Default `agentName` to `'glue'`; subagents pass through `AgentManager`. Add `gen_ai.operation.name=invoke_agent`, `gen_ai.provider.name`, `gen_ai.conversation.id`. Keep `agent.iteration.*` end-extras as Glue-specific keys alongside the new canonical ones. Commit.
3. **Rename `llm.stream` → `chat {modelId}`** with kind `chat` in `agent_core.dart:135`. Commit.
4. **Refactor `executeTool`** to take an optional pre-started span. Add a `Map<String, ObservabilitySpan> _pendingToolSpans` keyed by `call.id`. In the `ToolCallComplete` arm of `agent_core.dart:183`, start the `execute_tool {call.name}` span parented to the iteration span and stash it. In `executeTool`, look up and use that span instead of starting a new one; remove from the map on end. Drop the `llm.tool_call.start` / `llm.tool_call.complete` events from the chat span. Re-run test. Expected: PASS. Commit.
5. **Add `gen_ai.tool.call.arguments` and `gen_ai.tool.call.result`** as opt-in attributes (only when `captureMessages=true`) using `redactBody`. Commit.
6. **Add `glue.tool.source = 'mcp' | 'builtin' | 'subagent'`** attribute by inspecting the `Tool` implementation type. (Builtin tools live in `glue_harness/lib/src/tools/`, MCP tools are dispatched through `glue_harness/lib/src/mcp/`, subagent-spawning tools are in `glue_harness/lib/src/tools/subagent_tools.dart`.) Commit.

### Phase 5 — `invoke_workflow` for nested subagents

Goal: when a subagent spawns subagents (depth ≥ 1), the top-level coordinator span becomes `invoke_workflow`.

**Files:**
- Modify: `packages/glue_harness/lib/src/agent/agent_manager.dart` (line ~156)
- Test: `packages/glue_harness/test/agent/agent_manager_otel_test.dart` (new)

Tasks:

1. **Failing test:** spawn a subagent (depth 0 → 1) and assert the captured span is named `invoke_agent <subagent-id>` with `gen_ai.operation.name=invoke_agent`. Spawn a depth-1 → 2 nested subagent and assert the depth-1 span is `invoke_workflow ...` with `gen_ai.operation.name=invoke_workflow`. Run. Expected: FAIL.
2. **Update the span name and kind** in `AgentManager.spawnSubagent` based on `currentDepth`: depth 0 emits `invoke_agent`, depth ≥ 1 emits `invoke_workflow`. Add `gen_ai.workflow.name=<subagent task summary, max 80 chars>` on workflow spans. Commit.
3. **Add a parent span** wrapping `spawn_parallel_subagents` fan-out so the N child workflow spans share a parent. This requires a small change in `packages/glue_harness/lib/src/tools/subagent_tools.dart`. Commit.

### Phase 6 — Opt-in message and tool-definition capture

Goal: `captureMessages` flag enables the OTel-canonical structured message attributes.

**Files:**
- Modify: `packages/glue_harness/lib/src/observability/observability_config.dart` (`captureMessages` field)
- Modify: `packages/glue_harness/lib/src/config/glue_config.dart` (parse env + YAML)
- Modify: `packages/glue_harness/lib/src/agent/agent_core.dart` (emit canonical messages when flag on)
- Create: `packages/glue_harness/lib/src/observability/message_serializer.dart` (converts Glue `Message` to OTel JSON shape)
- Test: `packages/glue_harness/test/observability/message_serializer_test.dart`

Tasks:

1. **Failing test for `messageSerializerToOtelJson`.** Assert a `Message.user('hi')` serializes to `{role: 'user', parts: [{type: 'text', content: 'hi'}]}`. Assert a `Message.assistant` with text + tool calls serializes per the schema. Assert image parts emit `{type: 'image', mime: ..., bytes: N}` not the bytes themselves. Run. Expected: FAIL.
2. **Implement `message_serializer.dart`.** Reuse `redactBody` for text content. Commit.
3. **Add `captureMessages: bool`** to `OtelConfig` (default false). Wire to `OTEL_GLUE_CAPTURE_MESSAGES=1` env var in `glue_config.dart`. Commit.
4. **In `AgentCore.run`**, when `captureMessages=true`, attach `gen_ai.input.messages` (serialized conversation) and `gen_ai.system_instructions` (system prompt) at chat-span start; attach `gen_ai.output.messages` (single-element with assistant text + tool calls) at chat-span end. Commit.
5. **Add `gen_ai.tool.definitions`** (also gated by `captureMessages`) on the chat span — serialize the `allowedTools` list, cap at 16 KB. Commit.

### Phase 7 — Retry counter (smallest, most isolated)

Goal: when LLM/search/browser clients retry, the canonical `http.request.resend_count` is on each retry's span.

**Files:**
- Modify: `packages/glue_harness/lib/src/observability/logging_http_client.dart`
- Modify: provider clients that retry (currently `anthropic_client.dart`, `openai_client.dart` — confirm via `grep -rn "retry\|retries"`)
- Test: `cli/test/observability/logging_http_client_test.dart` (extend)

Tasks:

1. **Failing test:** drive a request through `LoggingHttpClient` twice in a row with a `request.headers['x-glue-resend-count'] = '1'` and assert the span has `http.request.resend_count=1`. Run. Expected: FAIL.
2. **Update `LoggingHttpClient.send`** to read the magic header, strip it before forwarding, and write `http.request.resend_count` to the span. Re-run test. Expected: PASS. Commit.
3. **Provider clients** set the header on retry attempts (one-line change in each retry loop). Commit.

### Phase 8 — `glue doctor` Otel block

Goal: `glue doctor` shows what conventions are being emitted so users can confirm compliance.

**Files:**
- Modify: `cli/lib/src/doctor/doctor.dart`
- Test: `cli/test/doctor/doctor_test.dart` (extend)

Single task: add an "OTel" block that reports:
- Whether OTLP export is configured (endpoint + headers redacted).
- Which conventions Glue currently emits: `gen-ai semconv`, `openinference`, `http semconv`.
- Whether `captureMessages` is on (with a warning if it is, since messages can contain user code).

---

## Risks and adversarial review

### 1. Span tree shape change breaks dashboards

Phase 4 splits tool calls into discrete spans. Anyone with a Phoenix dashboard counting `llm.tool_call_count` on `llm.stream` will see it stay zero. Mitigation: keep `llm.tool_call_count` on the renamed `chat` span, populated from the parent's known tool-call list. Dashboards built on the old name `llm.stream` still break and need a one-line edit to `chat`. Document this in the PR description.

### 2. High-cardinality span names

`POST /v1/messages` is fine. But if a provider exposes per-conversation URLs (e.g. `/v1/threads/{id}/messages` for OpenAI Assistants), the span name becomes high-cardinality. Mitigation: a small `_normalizeSpanPath` helper in `logging_http_client.dart` that masks UUID/id-shaped segments — `/v1/threads/{id}/messages` → `/v1/threads/:id/messages`. Glue doesn't currently call Assistants but search/browser providers might have similar patterns.

### 3. `gen_ai.input.messages` leaking secrets

Even with `redactBody`, structured JSON messages can contain things the regex misses (in-flight credentials in tool arguments, user-pasted secrets). Mitigation: gated behind `captureMessages=false` default; add a startup notice when the flag is on; document in the help text that this is for local debugging only.

### 4. `gen_ai.tool.definitions` payload bloat

Glue's full tool catalog is large. Without the 16 KB cap (described in Phase 6), every chat span balloons. Mitigation: cap + truncation marker, tested.

### 5. Provider-name enum drift

OTel adds providers to the enum periodically. If Glue hardcodes a list and a new provider ships, we either emit the wrong name or fall through to passthrough. Mitigation: passthrough is the default behavior — Glue never errors on an unknown provider, it just emits the Glue-internal id. Re-check the enum on every Glue release (add to release checklist).

### 6. Backward-compat across two attribute schemas

Dual-emission doubles the attribute count per span. Mitigation: at typical Glue volume (one trace tree per turn, maybe 5-20 spans), this is sub-KB and irrelevant. Document the cost in the PR description.

### 7. `service.namespace` collision

Setting `service.namespace=glue` could collide with a user who's already setting it via `OTEL_RESOURCE_ATTRIBUTES`. Mitigation: only emit the default when the user hasn't set it themselves (check `_config.resourceAttributes['service.namespace']` first).

---

## Acceptance criteria

### Phase 1 (HTTP semconv + span-kind table)
- Every span emitted by `LoggingHttpClient` carries `http.request.method`, `url.full`, `server.address`, `server.port`, `http.response.status_code`, `error.type` (normalized), plus the legacy `http.method`/`http.url`/`http.status_code` keys.
- Span names use `{METHOD} {path}` format.
- `OtlpHttpTraceSink` uses an explicit kind table (not a string heuristic).

### Phase 2 (chat-span GenAI dual-emit)
- Every LLM call's span carries `gen_ai.operation.name=chat`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.conversation.id`, plus the existing `openinference.span.kind=LLM` and `llm.model_name`.
- Token usage attributes appear under both `llm.token_count.*` and `gen_ai.usage.*`.

### Phase 3 (stream end)
- Every LLM call's span carries `gen_ai.response.finish_reasons`, `gen_ai.response.id`, `gen_ai.response.model` where the provider exposes them.

### Phase 4 (execute_tool spans)
- Every tool call produces a discrete `execute_tool {name}` span as a sibling of `chat {model}` under `invoke_agent {name}`.
- The span carries `gen_ai.tool.name`, `gen_ai.tool.call.id`, `gen_ai.tool.type=function`, `glue.tool.source`.
- `llm.tool_call.start` / `llm.tool_call.complete` events are gone from the chat span.

### Phase 5 (invoke_workflow)
- Top-level user turns are `invoke_agent`; nested subagents are `invoke_workflow`.
- Parallel subagent fan-out has a parent workflow span grouping the children.

### Phase 6 (opt-in messages)
- With `captureMessages=true`, every chat span carries `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.definitions` (capped at 16 KB).
- With `captureMessages=false` (default), none of those appear.

### Phase 7 (retry counter)
- Every retried HTTP request carries `http.request.resend_count`.

### Phase 8 (doctor)
- `glue doctor` reports the active OTel emission state.

### End-to-end verification (manual)
- Run `observe-llm start jaeger` from the `~/code/observe-llm` repo, set the OTel env vars, run a Glue session, and confirm in Jaeger that:
  - HTTP spans have `http.request.method`, `url.full`, `server.address`, etc.
  - Glue traces share a `service.namespace=glue` grouping.
- Repeat with `observe-llm start phoenix`; confirm Phoenix still renders the trace tree using OpenInference attributes (no regression).
- Repeat with `observe-llm start langfuse`; confirm Langfuse correctly identifies the model, provider, and token usage from the `gen_ai.*` attributes.

---

## Recommended execution order

1. Phase 1 (HTTP semconv + kind table) — purely additive, ships safely on its own.
2. Phase 2 (chat-span GenAI dual-emit) — additive, ships safely on its own.
3. Phase 3 (stream end) — touches every provider, ship after Phase 2 has soaked.
4. Phase 7 (retry counter) — small, isolated, can ship anytime after Phase 1.
5. Phase 8 (doctor) — depends on Phases 1-3; small.
6. Phase 4 (execute_tool spans) — biggest structural change, ship deliberately.
7. Phase 5 (invoke_workflow) — depends on Phase 4.
8. Phase 6 (opt-in messages) — final polish.

Each phase produces a working, mergeable, individually-revertible change. No phase requires breaking the previous schema.

---

## Open questions

1. **Should `service.namespace` default to `'glue'` or be left blank?** Defaulting helps Jaeger/Tempo grouping when a user runs Glue alongside other services through one Collector. Leaving blank avoids overriding user intent. Recommend: default to `'glue'` only when the user hasn't set it themselves.
2. **Do we ship Phase 4 (span-tree restructure) in the same release as Phases 1-3?** Phases 1-3 are pure dual-emit. Phase 4 changes the tree shape. Recommend: Phases 1-3 first release, Phase 4 in the next release with a clear changelog note.
3. **`gen_ai.usage.cache_creation.input_tokens` vs `gen_ai.usage.cache_creation_input_tokens`** — verify the exact spelling in the registry; the spec uses dot-separated namespacing but several backends accept either. Pin the spec-canonical form.
4. **Ollama provider name** — not in the OTel well-known enum. Passthrough as `'ollama'` is documented as a Glue extension. If OTel adds it later (likely), we drop the passthrough.
5. **Should `tool.approval` modal spans get `gen_ai.*` attributes?** Argument for: they're part of the GenAI workflow. Argument against: they're a Glue UX construct, not a GenAI operation. Recommend: no `gen_ai.*` keys; keep as Glue-specific INTERNAL span.

---

## Notes

This plan is grounded in:

- The current observability code in `packages/glue_harness/lib/src/observability/` and `packages/glue_harness/lib/src/agent/agent_core.dart`.
- The upstream OTel specs at <https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/>, <https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/>, and <https://opentelemetry.io/docs/specs/semconv/http/http-spans/>.
- The launcher registry in `~/code/observe-llm/src/registry/agents/` showing which sibling agents do (Gemini CLI) and don't (Claude Code, Codex, Goose) follow the GenAI semconv natively.
- The market research in `~/code/research-llmobservability/reports/` confirming GenAI semconv adoption across Langfuse, Phoenix, OpenLIT, Laminar, SigNoz.

The most important non-obvious conclusion:

> Dual-emit is the only correct strategy. Phoenix (and anyone reading OpenInference) needs the existing `llm.*` and `openinference.span.kind` attributes. Every newer backend prefers `gen_ai.*`. Glue can satisfy both for the cost of a few extra KV pairs per span — and avoids being the next agent that needs a Collector transform processor to render correctly.

The second most important conclusion:

> Splitting tool calls into their own `execute_tool` spans (Phase 4) is the single largest behavioral change. It's the right move for spec compliance and for per-tool latency analysis, but it changes the trace tree shape — anyone with dashboards built on the current shape needs to update them. Ship it deliberately, not in the same release as the dual-emit work.
