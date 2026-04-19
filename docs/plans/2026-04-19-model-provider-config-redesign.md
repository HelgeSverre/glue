# Model And Provider Config Redesign

Status: proposed
Owner: implementation agent
Date: 2026-04-19

## Goal

Make model/provider selection boring and predictable.

Glue should keep multi-provider support, but it should not fetch and display
every model a provider exposes by default. Provider APIs often return legacy
models, embedding models, audio/image models, moderation models, deprecated
models, and models that do not support tool calling. That makes the model
picker noisy and pushes complexity onto the user.

The desired behavior:

- curated model list by default
- easy custom providers
- easy OpenAI-compatible endpoints without awkward names
- credentials stored separately from model catalog
- optional remote catalog refresh later
- no provider API model fetching during normal startup

## Lessons From Other Tools

### OpenCode

OpenCode uses the `provider/model` model ID shape. It supports a `provider`
config block, custom providers, per-model options, and a separate `small_model`
for lightweight tasks like title generation. Credentials added through
`/connect` are stored separately from the project config.

Useful ideas to copy:

- Full model IDs: `anthropic/claude-sonnet-4-5`
- Separate `model` and `small_model`
- Custom provider blocks with explicit `models`
- Credentials separate from provider/model catalog
- Enabled/disabled provider filters
- Recommended model list rather than trusting provider API output

Do not copy blindly:

- Huge provider surface area on day one
- Automatic provider/model loading that makes the picker noisy
- Variants unless we have a clear UI for them

### GitHub Copilot And VS Code

Copilot keeps a curated supported-model list and makes availability depend on
client, plan, and capability. VS Code's model manager lets users add providers,
hide/show models, and filter by provider/capability. Copilot CLI BYOK is even
simpler: provider type, base URL, API key, and model.

Useful ideas to copy:

- Curated built-in model list
- Model visibility control
- Capability metadata such as `tools`, `vision`, `agent`
- "Bring your own key" without forcing every provider into a custom connector
- OpenAI-compatible endpoint as a generic adapter

## Proposed Concepts

### Provider

A provider is a named account or endpoint. Examples:

- `anthropic`
- `openai`
- `gemini`
- `mistral`
- `groq`
- `ollama`
- `openrouter`
- `work-azure`
- `local-vllm`

### Adapter

An adapter is the wire protocol implementation Glue uses.

Use `adapter`, not `openai_compatible`, in user-facing config.

Examples:

```yaml
providers:
  groq:
    name: Groq
    adapter: openai
    base_url: https://api.groq.com/openai/v1
    api_key: env:GROQ_API_KEY

  ollama:
    name: Ollama
    adapter: openai
    base_url: http://localhost:11434/v1
    api_key: none

  anthropic:
    name: Anthropic
    adapter: anthropic
    api_key: env:ANTHROPIC_API_KEY
```

`adapter: openai` means "speak the OpenAI Chat/Responses style API". It does
not mean the provider is OpenAI.

Supported adapters for the first pass:

- `anthropic`
- `openai`
- `gemini`
- `mistral` if native behavior is needed
- `openai` for Groq, Ollama, OpenRouter, vLLM, LM Studio, Azure-compatible
  gateways if the endpoint supports it

Optional later adapters:

- `azure_openai`
- `bedrock`
- `vertex`
- `copilot`

### Model Catalog

The catalog is a curated list of models Glue should show by default. It is not
the same as provider credentials. It can be bundled, local, or remote.

Recommended files:

```text
~/.glue/
  config.yaml
  credentials.json       # chmod 0600, optional if env vars are used
  models.yaml            # user overrides and additions
```

Bundled fallback:

```text
assets/models.yaml       # or lib/src/config/models.yaml
```

Reference example:

- `cli/docs/reference/models.yaml`

### Credential Storage

Keep credentials out of project config by default.

Credential resolution order:

1. environment variable from `api_key: env:NAME`
2. `~/.glue/credentials.json`
3. inline `api_key` only for throwaway/local configs
4. no key for local providers like Ollama

Suggested `credentials.json`:

```json
{
  "version": 1,
  "providers": {
    "anthropic": { "api_key": "sk-ant-..." },
    "openai": { "api_key": "sk-..." },
    "groq": { "api_key": "gsk_..." }
  }
}
```

The file should be created with `0600` permissions. On macOS, Keychain support
can be added later, but do not block the cleanup on it.

### Config Shape

Recommended `~/.glue/config.yaml`:

```yaml
model: anthropic/claude-sonnet-4-6
small_model: anthropic/claude-haiku-4-5

catalog:
  source: bundled
  local_path: ~/.glue/models.yaml
  remote_url: null
  refresh: manual # never | manual | daily

providers:
  anthropic:
    adapter: anthropic
    api_key: env:ANTHROPIC_API_KEY

  openai:
    adapter: openai
    base_url: https://api.openai.com/v1
    api_key: env:OPENAI_API_KEY

  gemini:
    adapter: gemini
    api_key: env:GEMINI_API_KEY

  mistral:
    adapter: mistral
    api_key: env:MISTRAL_API_KEY

  groq:
    adapter: openai
    base_url: https://api.groq.com/openai/v1
    api_key: env:GROQ_API_KEY

  ollama:
    adapter: openai
    base_url: http://localhost:11434/v1
    api_key: none

enabled_providers:
  - anthropic
  - openai
  - gemini
  - mistral
  - groq
  - ollama

hidden_models:
  - openai/gpt-4.1
```

Notes:

- `model` is always `provider_id/model_id`.
- `small_model` is for title generation, summarization, and other cheap tasks.
- `provider_id` is the key under `providers`.
- `model_id` is the key under `models` in the catalog.
- Unknown old config keys should warn at most, not crash startup.

## Model Picker Rules

Default picker should show:

- providers with credentials or `api_key: none`
- models from the curated catalog
- models with `capabilities` containing `tools`
- models not hidden
- models not marked deprecated

Default picker should not show:

- embedding models
- audio/image-only models
- moderation models
- legacy models
- models without streaming
- models without tool calling
- every raw provider model by default

Useful filters:

```text
@provider:openai
@capability:vision
@capability:local
@speed:fast
@cost:low
@visible:true
```

## Commands

Recommended command surface:

```text
/model
/model anthropic/claude-sonnet-4.6
/models
/providers
/provider add
/provider test anthropic
/models refresh ollama
/models import openrouter
```

`/models refresh` should be explicit. It should not run automatically during
normal startup.

`/models import` can fetch provider models and write selected entries into
`~/.glue/models.yaml`, but it should ask the user which models to keep.

## Remote Catalog Option

If Glue later gets a backend or a maintained GitHub-hosted catalog, support a
remote catalog as an optional layer.

Example:

```yaml
catalog:
  source: remote
  remote_url: https://raw.githubusercontent.com/helgesverre/glue/main/catalog/models.yaml
  refresh: daily
  cache_path: ~/.glue/cache/models.yaml
  fallback: bundled
```

Rules:

- Startup must work offline.
- Remote fetch must have a short timeout.
- Failed refresh must use cached or bundled catalog silently unless debug is on.
- Remote catalog must not inject credentials.
- User `~/.glue/models.yaml` overrides remote and bundled entries.

Merge order:

1. bundled catalog
2. remote catalog if enabled and available
3. local user catalog
4. project-local overrides if added later

## Connector Interface

Implementation sketch:

```dart
abstract class ProviderConnector {
  String get id;
  String get displayName;
  String get adapter;

  Future<ProviderHealth> validate(ProviderConfig config);

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

OpenAI-compatible endpoints should use the same connector:

```dart
class OpenAiAdapterConnector implements ProviderConnector {
  // Used by OpenAI, Groq, Ollama, OpenRouter, vLLM, LM Studio, etc.
}
```

Provider-specific differences should live in config and small adapter shims,
not in a giant switch throughout the app.

## Migration From Current Config

Current state:

- `LlmProvider` enum is fixed to Anthropic, OpenAI, Mistral, Ollama.
- API keys live as provider-specific fields on `GlueConfig`.
- `ModelRegistry` is hardcoded in Dart.
- Provider/model inference happens in `GlueConfig.load`.
- Model discovery/listing code exists and can produce too much noise.

Target state:

- provider IDs are strings, not enum-only
- built-in providers are catalog entries
- credentials are resolved through a `CredentialStore`
- model catalog can be loaded from YAML
- Dart registry becomes generated data or simple catalog parser
- custom providers do not need code changes if they use `adapter: openai`

Suggested migration path:

1. Add catalog parser and load `cli/docs/reference/models.yaml` as the shape.
2. Keep existing Dart `ModelRegistry` as fallback during migration.
3. Add `provider/model` parsing.
4. Add `ProviderConfig` with `adapter`, `base_url`, and credential reference.
5. Add `CredentialStore`.
6. Convert built-in providers to config-backed connectors.
7. Remove provider enum from user-facing config.
8. Keep enum internally only if useful, but do not expose it.
9. Make model discovery opt-in only.
10. Update docs and tests.

## Acceptance Criteria

- `glue --model anthropic/claude-sonnet-4.6` works.
- `glue --model groq/qwen/qwen3-coder` works when Groq is configured with
  `adapter: openai`.
- Ollama works with `api_key: none`.
- Startup does not fetch provider model lists.
- Model picker defaults to curated, tool-capable models.
- User can add one OpenAI-compatible provider without code changes.
- User can hide noisy models.
- Stale old provider config does not crash startup.
- Tests cover provider/model parsing, credential resolution, catalog merge
  order, and model picker filtering.

## Source Notes

- OpenCode uses `provider/model` IDs, provider config blocks, `small_model`,
  custom provider model entries, and separate credential storage.
- OpenCode also supports enabled/disabled providers and recommended models.
- GitHub Copilot uses curated model availability and model visibility concepts.
- Copilot CLI BYOK shows the simplest useful shape: provider type, base URL,
  API key, and model.
- VS Code's model picker supports provider/capability/visibility filtering.

Useful references:

- https://opencode.ai/docs/config/
- https://opencode.ai/docs/providers/
- https://opencode.ai/docs/models/
- https://docs.github.com/en/copilot/reference/ai-models/supported-models
- https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models
- https://code.visualstudio.com/docs/copilot/customization/language-models
