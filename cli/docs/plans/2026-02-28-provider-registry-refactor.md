# Add Mistral Provider + Future Registry Refactor Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Phase A: Add Mistral Provider (Current Sprint)

**Goal:** Add Mistral as a fourth LLM provider using the existing enum + switch pattern. Mistral uses an OpenAI-compatible API, so the `OpenAiClient` handles it with a different `baseUrl`.

**Approach:** Add `mistral` to the `LlmProvider` enum, add cases to all 8 existing switch statements, add curated models, add `mistralApiKey` to `GlueConfig`, add model listing, update tests.

**Files touched:**
- Modify: `cli/lib/src/config/glue_config.dart` (enum + config + validation + load)
- Modify: `cli/lib/src/llm/llm_factory.dart` (3 switch cases)
- Modify: `cli/lib/src/llm/model_lister.dart` (1 switch case + shared helper)
- Modify: `cli/lib/src/config/model_registry.dart` (1 switch case + model entries)
- Modify: `cli/lib/src/agent/agent_manager.dart` (1 switch case)
- Modify: `cli/test/config/glue_config_test.dart`
- Modify: `cli/test/config/model_registry_test.dart`
- Modify: `cli/test/llm/llm_factory_test.dart`
- Modify: `cli/test/llm/model_lister_test.dart`

---

### Task 1: Add `LlmProvider.mistral` enum + `GlueConfig` support

**Files:**
- Modify: `cli/lib/src/config/glue_config.dart`
- Modify: `cli/test/config/glue_config_test.dart`

**Step 1: Add `mistral` to the enum**

In `cli/lib/src/config/glue_config.dart`, change:
```dart
enum LlmProvider { anthropic, openai, ollama }
```
to:
```dart
enum LlmProvider { anthropic, openai, mistral, ollama }
```

**Step 2: Add `mistralApiKey` field to `GlueConfig`**

Add field:
```dart
final String? mistralApiKey;
```

Add to constructor parameter list (after `openaiApiKey`):
```dart
this.mistralApiKey,
```

**Step 3: Update `validate()`**

Replace the key switch and error message with:
```dart
final key = switch (provider) {
  LlmProvider.anthropic => anthropicApiKey,
  LlmProvider.openai => openaiApiKey,
  LlmProvider.mistral => mistralApiKey,
  LlmProvider.ollama => '', // unreachable
};
if (key == null || key.isEmpty) {
  final envVar = switch (provider) {
    LlmProvider.anthropic => 'ANTHROPIC_API_KEY',
    LlmProvider.openai => 'OPENAI_API_KEY',
    LlmProvider.mistral => 'MISTRAL_API_KEY',
    LlmProvider.ollama => '',
  };
  throw ConfigError(
    'Missing API key for provider ${provider.name}. '
    'Set $envVar or add it to ~/.glue/config.yaml',
  );
}
```

**Step 4: Update `apiKey` getter**

```dart
return switch (provider) {
  LlmProvider.anthropic => anthropicApiKey!,
  LlmProvider.openai => openaiApiKey!,
  LlmProvider.mistral => mistralApiKey!,
  LlmProvider.ollama => '',
};
```

**Step 5: Update `copyWith()`**

Add `mistralApiKey: mistralApiKey,` to the `GlueConfig(...)` constructor call.

**Step 6: Add Mistral key resolution to `GlueConfig.load()`**

After the `openaiKey` resolution block (around line 181), add:
```dart
final mistralKey = Platform.environment['MISTRAL_API_KEY'] ??
    Platform.environment['GLUE_MISTRAL_API_KEY'] ??
    (fileConfig?['mistral'] as Map?)?['api_key'] as String?;
```

Note: There's already a `mistralApiKey` being read in section 2e (PDF config) for OCR purposes from `pdfSection?['mistral_api_key']`. The new `mistralKey` is the top-level LLM provider key from `mistral.api_key` in YAML / `MISTRAL_API_KEY` env var. These are the same env var but different YAML paths — the top-level one for the LLM provider, the nested one for PDF OCR. They can share the same env var value.

Pass `mistralApiKey: mistralKey,` in the return `GlueConfig(...)` call.

**Step 7: Add tests**

Add to `cli/test/config/glue_config_test.dart`:
```dart
test('resolves mistral provider', () {
  final config = GlueConfig(
    provider: LlmProvider.mistral,
    model: 'mistral-large-latest',
    mistralApiKey: 'mk-test',
  );
  expect(config.provider, LlmProvider.mistral);
  expect(config.model, 'mistral-large-latest');
});

test('validates mistral API key', () {
  final config = GlueConfig(
    provider: LlmProvider.mistral,
    model: 'mistral-large-latest',
    mistralApiKey: 'mk-test',
  );
  config.validate(); // Should not throw
});

test('validates missing mistral API key', () {
  expect(
    () => GlueConfig(provider: LlmProvider.mistral).validate(),
    throwsA(isA<ConfigError>()),
  );
});

test('apiKey getter returns mistral key', () {
  final config = GlueConfig(
    provider: LlmProvider.mistral,
    model: 'mistral-large-latest',
    mistralApiKey: 'mk-test',
  );
  expect(config.apiKey, 'mk-test');
});
```

**Step 8: Run tests**

Run: `cd cli && dart test test/config/glue_config_test.dart`
Expected: all pass

**Step 9: Commit**

```bash
git add cli/lib/src/config/glue_config.dart cli/test/config/glue_config_test.dart
git commit -m "feat: add LlmProvider.mistral enum and GlueConfig support"
```

---

### Task 2: Add Mistral to `LlmClientFactory` and `AgentManager`

**Files:**
- Modify: `cli/lib/src/llm/llm_factory.dart`
- Modify: `cli/lib/src/agent/agent_manager.dart`
- Modify: `cli/test/llm/llm_factory_test.dart`

**Step 1: Add Mistral case to `create()`**

In `llm_factory.dart`, add to the switch in `create()` (before `LlmProvider.ollama`):
```dart
LlmProvider.mistral => OpenAiClient(
    httpClient: _httpClient,
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    baseUrl: 'https://api.mistral.ai',
  ),
```

**Step 2: Add Mistral case to `createFromEntry()`**

```dart
LlmProvider.mistral => config.mistralApiKey ?? '',
```

**Step 3: Add Mistral case to `createFromProfile()`**

```dart
LlmProvider.mistral => config.mistralApiKey ?? '',
```

**Step 4: Add Mistral case to `AgentManager._apiKeyFor()`**

In `agent_manager.dart`:
```dart
String _apiKeyFor(LlmProvider provider) => switch (provider) {
      LlmProvider.anthropic => config.anthropicApiKey ?? '',
      LlmProvider.openai => config.openaiApiKey ?? '',
      LlmProvider.mistral => config.mistralApiKey ?? '',
      LlmProvider.ollama => '',
    };
```

**Step 5: Add test**

Add to `cli/test/llm/llm_factory_test.dart`:
```dart
test('creates OpenAiClient for mistral provider', () {
  final factory = LlmClientFactory();
  final client = factory.create(
    provider: LlmProvider.mistral,
    model: 'mistral-large-latest',
    apiKey: 'mk-test',
    systemPrompt: 'test',
  );
  expect(client, isA<OpenAiClient>());
});
```

Add import if not present:
```dart
import 'package:glue/src/llm/openai_client.dart';
```

(It's already imported.)

**Step 6: Run tests**

Run: `cd cli && dart test test/llm/llm_factory_test.dart`
Expected: all pass

**Step 7: Commit**

```bash
git add cli/lib/src/llm/llm_factory.dart cli/lib/src/agent/agent_manager.dart cli/test/llm/llm_factory_test.dart
git commit -m "feat: add Mistral cases to LlmClientFactory and AgentManager"
```

---

### Task 3: Add Mistral model listing

**Files:**
- Modify: `cli/lib/src/llm/model_lister.dart`
- Modify: `cli/test/llm/model_lister_test.dart`

**Step 1: Extract shared OpenAI-compatible listing helper**

The existing `_listOpenAi` method hardcodes the OpenAI URL. Refactor it into `_listOpenAiCompat(apiKey, baseUrl)` so both OpenAI and Mistral can use it:

Replace `_listOpenAi` with:
```dart
Future<List<ModelInfo>> _listOpenAiCompat(String apiKey, String baseUrl) async {
  final uri = Uri.parse(baseUrl).resolve('/v1/models');
  final response = await _http.get(uri, headers: {
    'Authorization': 'Bearer $apiKey',
  }).timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw Exception('API error ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final data = json['data'] as List? ?? [];
  final models = data.map((m) {
    final map = m as Map<String, dynamic>;
    return ModelInfo(id: map['id'] as String? ?? '');
  }).toList();
  models.sort((a, b) => a.id.compareTo(b.id));
  return models;
}
```

**Step 2: Update the switch in `list()`**

Add `mistralBaseUrl` parameter and update switch:
```dart
Future<List<ModelInfo>> list({
  required LlmProvider provider,
  String? apiKey,
  String ollamaBaseUrl = 'http://localhost:11434',
}) async {
  return switch (provider) {
    LlmProvider.ollama => _listOllama(ollamaBaseUrl),
    LlmProvider.openai => _listOpenAiCompat(apiKey ?? '', 'https://api.openai.com'),
    LlmProvider.mistral => _listOpenAiCompat(apiKey ?? '', 'https://api.mistral.ai'),
    LlmProvider.anthropic => _listAnthropic(apiKey ?? ''),
  };
}
```

**Step 3: Add test**

Add to `cli/test/llm/model_lister_test.dart`:
```dart
group('Mistral', () {
  test('parses /v1/models response with Bearer auth', () async {
    final client = http_testing.MockClient((req) async {
      expect(req.url.host, 'api.mistral.ai');
      expect(req.url.path, '/v1/models');
      expect(req.headers['Authorization'], 'Bearer test-key');
      return http.Response(
          jsonEncode({
            'data': [
              {'id': 'mistral-large-latest'},
              {'id': 'mistral-small-latest'},
              {'id': 'codestral-latest'},
            ]
          }),
          200);
    });
    final lister = ModelLister(httpClient: client);
    final models = await lister.list(
      provider: LlmProvider.mistral,
      apiKey: 'test-key',
    );
    expect(models, hasLength(3));
    // Sorted alphabetically
    expect(models[0].id, 'codestral-latest');
    expect(models[1].id, 'mistral-large-latest');
    expect(models[2].id, 'mistral-small-latest');
  });
});
```

**Step 4: Run tests**

Run: `cd cli && dart test test/llm/model_lister_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/llm/model_lister.dart cli/test/llm/model_lister_test.dart
git commit -m "feat: add Mistral model listing with shared OpenAI-compat helper"
```

---

### Task 4: Add Mistral curated models to `ModelRegistry`

**Files:**
- Modify: `cli/lib/src/config/model_registry.dart`
- Modify: `cli/test/config/model_registry_test.dart`

**Step 1: Add Mistral case to `available()`**

```dart
LlmProvider.mistral =>
  config.mistralApiKey != null && config.mistralApiKey!.isNotEmpty,
```

**Step 2: Add Mistral model entries**

After the Ollama section in the `models` list, add:
```dart
// ── Mistral ─────────────────────────────────────────────
ModelEntry(
  displayName: 'Mistral Large',
  modelId: 'mistral-large-latest',
  provider: LlmProvider.mistral,
  capabilities: {ModelCapability.coding, ModelCapability.reasoning},
  cost: CostTier.high,
  speed: SpeedTier.standard,
  tagline: 'Flagship multimodal',
  isDefault: true,
),
ModelEntry(
  displayName: 'Mistral Small',
  modelId: 'mistral-small-latest',
  provider: LlmProvider.mistral,
  capabilities: {ModelCapability.fast, ModelCapability.coding},
  cost: CostTier.low,
  speed: SpeedTier.fast,
  tagline: 'Fast and efficient',
),
ModelEntry(
  displayName: 'Codestral',
  modelId: 'codestral-latest',
  provider: LlmProvider.mistral,
  capabilities: {ModelCapability.coding, ModelCapability.fast},
  cost: CostTier.medium,
  speed: SpeedTier.fast,
  tagline: 'Code specialist',
),
```

**Step 3: Add tests**

Add to `cli/test/config/model_registry_test.dart`:
```dart
test('contains Mistral models', () {
  final mistral = ModelRegistry.forProvider(LlmProvider.mistral);
  expect(mistral.length, 3);
  expect(mistral.any((m) => m.modelId == 'mistral-large-latest'), isTrue);
  expect(mistral.any((m) => m.modelId == 'codestral-latest'), isTrue);
});

test('Mistral default model is mistral-large-latest', () {
  final def = ModelRegistry.defaultFor(LlmProvider.mistral);
  expect(def.modelId, 'mistral-large-latest');
});

test('available includes Mistral when key set', () {
  final config = GlueConfig(mistralApiKey: 'test-key');
  final available = ModelRegistry.available(config);
  expect(available.any((m) => m.provider == LlmProvider.mistral), isTrue);
});

test('available excludes Mistral when key missing', () {
  final config = GlueConfig();
  final available = ModelRegistry.available(config);
  expect(available.any((m) => m.provider == LlmProvider.mistral), isFalse);
});
```

The existing test `'available includes all providers when both keys set'` uses `containsAll(LlmProvider.values)` — update it to include `mistralApiKey`:
```dart
test('available includes all providers when all keys set', () {
  final configAll = GlueConfig(
    anthropicApiKey: 'sk-ant',
    openaiApiKey: 'sk-oai',
    mistralApiKey: 'mk-test',
  );
  final available = ModelRegistry.available(configAll);
  final providers = available.map((m) => m.provider).toSet();
  expect(providers, containsAll(LlmProvider.values));
});
```

**Step 4: Run tests**

Run: `cd cli && dart test test/config/model_registry_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/config/model_registry.dart cli/test/config/model_registry_test.dart
git commit -m "feat: add Mistral curated models to ModelRegistry"
```

---

### Task 5: Final verification

**Step 1: Run analyzer**

Run: `cd cli && dart analyze`
Expected: zero new warnings/errors

**Step 2: Run full test suite**

Run: `cd cli && dart test`
Expected: all pass, no regressions

**Step 3: Format**

Run: `cd cli && dart format .`

---

## Phase B: Provider Registry Refactor (Deferred)

**When to do this:** When adding provider #5 or #6, or when building a settings UI that needs config introspection.

**Goal:** Replace the `LlmProvider` enum + switch statements with a self-describing provider registry. Adding a new provider should require only one class + one registration line — zero switches, zero per-provider config fields.

### Current State (After Phase A)

After Phase A, the codebase has:
- `LlmProvider` enum with 4 values: `anthropic`, `openai`, `mistral`, `ollama`
- 8 switch statements across 5 files that must be updated for each new provider
- 4 per-provider API key/URL fields on `GlueConfig`: `anthropicApiKey`, `openaiApiKey`, `mistralApiKey`, `ollamaBaseUrl`
- `ModelLister` with a shared `_listOpenAiCompat()` helper (from Phase A)
- `LlmClientFactory` with provider-specific switch dispatch

### Target Architecture

```
┌─────────────────────────────────────────────────────┐
│                 ProviderRegistry                     │
│  register(provider) / get(id) / requireCapability()  │
│                                                      │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │
│  │  Anthropic    │ │   OpenAI     │ │   Mistral    │ │
│  │  Provider     │ │  Provider    │ │  Provider    │ │
│  │              │ │              │ │              │ │
│  │ configSpec[] │ │ configSpec[] │ │ configSpec[] │ │
│  │ curatedModels│ │ curatedModels│ │ curatedModels│ │
│  │ createClient │ │ createClient │ │ createClient │ │
│  │ listModels   │ │ listModels   │ │ listModels   │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ │
└─────────────────────────────────────────────────────┘
           ▲                           ▲
           │                           │
    ConfigResolver              GlueConfig
    (env → yaml → defaults)    (exposes registry + resolver)
```

Each provider class implements:
- `LlmProviderDefinition` — identity (`id`, `displayName`), config spec, curated models
- `ChatCapability` — `createChatClient()`
- `ModelListingCapability` — `listModels()`

### Migration Steps (A → B)

#### B1: Create foundation types

Create `cli/lib/src/llm/config_spec.dart`:
- `ConfigKeySpec` — declares a config key a provider needs (key name, label, type, env vars, yaml path, default)
- `ConfigValueType` enum — `string`, `secret`, `url`, `bool`, etc.
- `ResolvedProviderConfig` — bag of resolved key-value pairs with `getString()` / `requireString()`
- `ConfigResolver` — resolves config from env → yaml → defaults given a list of `ConfigKeySpec`

This is pure new code, no existing files change.

#### B2: Create provider interfaces

Create `cli/lib/src/llm/provider_definition.dart`:
- `LlmProviderDefinition` interface — `id`, `displayName`, `configSpec`, `curatedModels`, `defaultModelId`
- `ChatCapability` interface — `createChatClient({httpClient, config, model, systemPrompt})`
- `ModelListingCapability` interface — `listModels({httpClient, config})`

No existing files change.

#### B3: Create shared OpenAI-compatible helper

Create `cli/lib/src/llm/providers/openai_compat.dart`:
- `listOpenAiCompatModels()` — shared model listing for OpenAI-compatible APIs
- `createOpenAiCompatClient()` — shared client factory wrapping `OpenAiClient`

Used by OpenAI, Mistral, and future OpenAI-compatible providers. No existing files change.

#### B4: Create provider implementations

Create one file per provider in `cli/lib/src/llm/providers/`:
- `anthropic_provider.dart` — `AnthropicProvider implements LlmProviderDefinition, ChatCapability, ModelListingCapability`
- `openai_provider.dart` — `OpenAiProvider` (delegates to openai_compat)
- `ollama_provider.dart` — `OllamaProvider`
- `mistral_provider.dart` — `MistralProvider` (delegates to openai_compat)

Each provider class:
1. Declares `configSpec` with env vars and yaml paths matching current resolution logic
2. Declares `curatedModels` matching current `ModelRegistry.models` entries for that provider
3. Implements `createChatClient()` matching current `LlmClientFactory.create()` logic
4. Implements `listModels()` matching current `ModelLister` logic

No existing files change yet — these are additive.

#### B5: Create `ProviderRegistry`

Create `cli/lib/src/llm/provider_registry.dart`:
- `ProviderRegistry` class — `register()`, `get()`, `has()`, `all`, `ids`, `requireCapability<T>()`, `allModels`, `configured(resolver)`
- `defaultProviderRegistry()` top-level function — creates registry with all 4 built-in providers

No existing files change.

#### B6: Wire into `GlueConfig` — replace per-provider fields

This is the critical migration step. Modify `cli/lib/src/config/glue_config.dart`:

1. Add `ProviderRegistry providerRegistry` and `ConfigResolver configResolver` fields
2. In `GlueConfig.load()`, build a `ConfigResolver(env: Platform.environment, yaml: fileConfig ?? {})`
3. **Remove** `anthropicApiKey`, `openaiApiKey`, `mistralApiKey` fields
4. Replace the `apiKey` getter with:
   ```dart
   String get apiKey {
     if (provider == LlmProvider.ollama) return '';
     validate();
     final def = providerRegistry.get(provider.name);
     final cfg = configResolver.resolve(def.id, def.configSpec);
     return cfg.requireString('apiKey');
   }
   ```
5. Replace `validate()` similarly — use registry to check if the provider is configured
6. Add `apiKeyFor(LlmProvider provider)` method using registry
7. Update `copyWith()` to pass through registry + resolver

#### B7: Replace `LlmClientFactory` switches with registry

Modify `cli/lib/src/llm/llm_factory.dart`:

1. Replace `create()` switch with:
   ```dart
   LlmClient create({...}) {
     final provider = registry.requireCapability<ChatCapability>(providerName);
     final def = registry.get(providerName);
     final cfg = resolver.resolve(def.id, def.configSpec);
     return provider.createChatClient(httpClient: _httpClient, config: cfg, model: model, systemPrompt: systemPrompt);
   }
   ```
2. Remove `createFromEntry()` and `createFromProfile()` API key switches — delegate to registry
3. Factory now takes `ProviderRegistry` + `ConfigResolver` as constructor params

#### B8: Replace `ModelLister` with registry delegation

Modify `cli/lib/src/llm/model_lister.dart`:

1. Replace `list()` switch with registry lookup:
   ```dart
   Future<List<ModelInfo>> list({required String providerId, ...}) async {
     final provider = registry.requireCapability<ModelListingCapability>(providerId);
     final def = registry.get(providerId);
     final cfg = resolver.resolve(def.id, def.configSpec);
     return provider.listModels(httpClient: _http, config: cfg);
   }
   ```
2. Remove `_listOllama`, `_listAnthropic`, `_listOpenAiCompat` — these live in provider classes now

#### B9: Replace `ModelRegistry.available()` with registry

Modify `cli/lib/src/config/model_registry.dart`:

1. Replace the `available()` switch with `ProviderRegistry.availableModels(resolver)`
2. Optionally: move the static `models` list into provider `curatedModels` and aggregate from registry

#### B10: Replace `AgentManager._apiKeyFor` with config method

Modify `cli/lib/src/agent/agent_manager.dart`:

1. Replace `_apiKeyFor` switch with `config.apiKeyFor(provider)` which uses the registry

#### B11: Update barrel exports

Add new exports to `cli/lib/glue.dart`:
```dart
export 'src/llm/config_spec.dart' show ConfigKeySpec, ConfigValueType, ResolvedProviderConfig, ConfigResolver;
export 'src/llm/provider_definition.dart' show LlmProviderDefinition, ChatCapability, ModelListingCapability;
export 'src/llm/provider_registry.dart' show ProviderRegistry;
export 'src/llm/providers/anthropic_provider.dart' show AnthropicProvider;
export 'src/llm/providers/openai_provider.dart' show OpenAiProvider;
export 'src/llm/providers/ollama_provider.dart' show OllamaProvider;
export 'src/llm/providers/mistral_provider.dart' show MistralProvider;
```

### What Phase B achieves

| Before (Phase A) | After (Phase B) |
|---|---|
| 8 switch statements across 5 files | 0 switch statements on provider |
| 4 per-provider fields on GlueConfig | Registry + resolver, no per-provider fields |
| Adding provider = touch 6 files, 8 switches | Adding provider = 1 class + 1 registration line |
| Model listing logic in ModelLister | Model listing logic in each provider |
| Client creation logic in LlmClientFactory | Client creation logic in each provider |
| Config resolution scattered in GlueConfig.load() | Config resolution via declarative ConfigKeySpec |

### When Phase B becomes worth it

- **5+ providers**: The switch maintenance burden becomes real
- **Settings UI**: ConfigKeySpec enables rendering config forms without hardcoding
- **Plugin system**: Third-party providers can register without forking
- **Capability gating**: Different providers supporting different features (embeddings, voice, vision) becomes type-safe
