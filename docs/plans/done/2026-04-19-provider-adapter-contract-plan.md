# Provider Adapter Contract Plan

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Make model/provider support extensible without letting provider-specific API
details leak through the app.

The existing model/provider redesign covers user-facing configuration and the
curated catalog. This plan goes one layer deeper: it defines the internal
contract between Glue's agent loop and provider adapters.

## Current Code Context

Relevant files:

- `lib/src/config/glue_config.dart`
- `lib/src/config/model_registry.dart`
- `lib/src/llm/llm_factory.dart`
- `lib/src/llm/message_mapper.dart`
- `lib/src/llm/anthropic_client.dart`
- `lib/src/llm/openai_client.dart`
- `lib/src/llm/ollama_client.dart`
- `lib/src/llm/model_lister.dart`
- `lib/src/llm/model_discovery.dart`
- `lib/src/agent/agent_core.dart`
- `lib/src/core/service_locator.dart`
- `lib/src/app/session_runtime.dart`

Current shape:

- `LlmProvider` is an enum with `anthropic`, `openai`, `mistral`, `ollama`.
- `GlueConfig` stores provider-specific API key fields.
- `ModelRegistry` is a Dart hardcoded catalog keyed by enum provider.
- `LlmClientFactory` switches on `LlmProvider`.
- `MessageMapper` already acts as a provider-specific translation layer.
- `AgentCore` uses provider-neutral `Message`, `ToolCall`, `ToolResult`, and
  `LlmChunk`.
- Mistral currently reuses `OpenAiClient` with a Mistral base URL.
- Model discovery can fetch provider model lists and cache them, which conflicts
  with the desired curated-by-default picker.

## Architectural Risk

If provider support grows by adding more enum values and switches, every new
provider will touch config loading, model registry, client factory, model
discovery, title generation, session metadata, UI formatting, tests, and docs.
That is shotgun surgery.

The better boundary is:

```text
App/AgentCore -> Glue-native LLM contract -> ProviderAdapter -> vendor API
```

Provider quirks should stay in adapters and compatibility profiles.

## Glue-Native Contract

Keep the app and agent loop provider-neutral.

Recommended internal types:

```dart
class ProviderId {
  final String value; // "anthropic", "groq", "local-vllm"
}

class ModelRef {
  final String providerId;
  final String modelId; // may contain slashes
}

class ProviderConfig {
  final String id;
  final String name;
  final String adapter; // anthropic | openai | gemini | mistral
  final Uri? baseUrl;
  final String compatibility; // openai | groq | ollama | openrouter | vllm
  final Map<String, String> requestHeaders;
  final CredentialRef credential;
}

class ModelConfig {
  final ModelRef ref;
  final String displayName;
  final Set<ModelCapability> capabilities;
  final int? contextWindow;
  final int? maxOutputTokens;
  final bool recommended;
}
```

Existing `Message`, `ToolCall`, `ToolResult`, and `LlmChunk` are already close
to the right app-facing contract. Expand them only where real adapter needs
force it.

## Capability Contract

The catalog should describe what Glue can rely on, not just what the vendor
calls the model.

Required capabilities:

- `chat`
- `streaming`
- `tools`
- `parallel_tools`
- `vision`
- `files`
- `json`
- `reasoning`
- `coding`
- `local`
- `browser`
- `binary_tool_results`

Recommended model fields:

```yaml
capabilities: [chat, streaming, tools, json, coding]
context_window: 200000
max_output_tokens: 8192
tool_calling:
  supported: true
  parallel: true
  argument_format: json_object
streaming:
  supported: true
  emits_tool_call_start: true
tool_results:
  images: true
  binary: false
reasoning:
  effort_control: true
  summary_control: false
```

Rules:

- The app should check capabilities before enabling features.
- Missing capability means false/unknown, not "probably supported".
- Providers may override model-level defaults.
- Remote catalog updates may add capabilities but must not remove local user
  overrides.

## OpenAI-Compatible Profiles

Use `adapter: openai` as the user-facing shape, but keep a separate
compatibility profile for known quirks.

Example:

```yaml
providers:
  groq:
    adapter: openai
    compatibility: groq
    base_url: https://api.groq.com/openai/v1

  ollama:
    adapter: openai
    compatibility: ollama
    base_url: http://localhost:11434/v1
    auth:
      api_key: none

  openrouter:
    adapter: openai
    compatibility: openrouter
    base_url: https://openrouter.ai/api/v1
    request_headers:
      HTTP-Referer: https://getglue.dev
      X-Title: Glue
```

`adapter` picks the wire protocol. `compatibility` tunes provider-specific
behavior.

Possible compatibility knobs:

- auth header shape
- required request headers
- base path normalization
- whether `/models` exists
- whether streaming tool call deltas are reliable
- whether arguments stream as partial JSON
- whether image input is accepted in chat messages
- whether tool results can contain images
- error response parser
- model ID prefix handling

Avoid user-facing names like `openai_compatible`. They describe implementation,
not intent.

## Adapter Interface

First-pass interface:

```dart
abstract class ProviderAdapter {
  String get adapterId;

  Future<ProviderHealth> validate(ProviderConfig provider);

  LlmClient createClient({
    required ProviderConfig provider,
    required ModelConfig model,
    required String systemPrompt,
  });

  Future<List<ModelConfig>> discoverModels(ProviderConfig provider) async {
    return const [];
  }
}
```

Keep `discoverModels` optional and explicit. It should not run during normal
startup.

Initial implementations:

- `AnthropicAdapter`
- `OpenAiAdapter`
- `GeminiAdapter`
- `MistralAdapter` only if native behavior is needed

The current `OpenAiClient` can probably back OpenAI, Mistral, Groq, Ollama,
OpenRouter, vLLM, and LM Studio after the base URL and compatibility knobs are
moved into config.

## Credential Boundary

Credentials should be resolved before adapter creation.

Recommended shape:

```dart
abstract class CredentialStore {
  Future<String?> resolve(CredentialRef ref, {required String providerId});
}

sealed class CredentialRef {}
class EnvCredential extends CredentialRef { final String name; }
class StoredCredential extends CredentialRef { final String key; }
class InlineCredential extends CredentialRef { final String value; }
class NoCredential extends CredentialRef {}
```

Resolution order:

1. env var
2. `~/.glue/credentials.json`
3. inline key with warning
4. no key for local providers

Do not let adapters read `Platform.environment` directly.

## Migration Plan

1. Add `ModelRef.parse` that splits on the first slash only.
   `groq/qwen/qwen3-coder` means provider `groq`, model `qwen/qwen3-coder`.
2. Add catalog parser for `cli/docs/reference/models.yaml`.
3. Add provider and model config data classes while keeping `LlmProvider`.
4. Add `CredentialStore` and resolve credentials into `ProviderConfig`.
5. Add `ProviderAdapterRegistry`.
6. Change `LlmClientFactory` to accept `ProviderConfig + ModelConfig`.
7. Keep enum-backed provider loading as a compatibility path.
8. Convert `ModelRegistry` into a catalog-backed facade.
9. Make `ModelDiscovery` opt-in and write discoveries to user overrides.
10. Remove user-facing enum provider assumptions after one compatibility pass.

## Tests

Add tests for:

- `ModelRef.parse` with model IDs that contain slashes
- catalog parser and merge order
- credential resolution order
- `adapter: openai` with `compatibility: groq`
- `adapter: openai` with `compatibility: ollama` and no API key
- provider validation failure does not crash model picker
- startup does not call model discovery
- title model resolution with `provider/model` IDs
- session metadata stores both `provider_id` and full `model_ref`

## Acceptance Criteria

- `glue --model anthropic/claude-sonnet-4.6` resolves through catalog data.
- `glue --model groq/qwen/qwen3-coder` parses correctly.
- Custom OpenAI-compatible providers do not require Dart code changes.
- App/agent code does not switch on provider enum for normal requests.
- Existing config still works with warnings where needed.
- Model discovery is manual only.
- Provider quirks are isolated to adapters or compatibility profiles.

## Open Questions

- Should sessions store `model_ref` only, or also store denormalized provider
  display name and adapter ID for replay/debugging?
- Should `compatibility` default to provider ID when omitted?
- Should catalog schema live as generated Dart for startup speed, or parsed YAML
  directly?
- Should inline credentials be allowed at all, or only behind a debug flag?
