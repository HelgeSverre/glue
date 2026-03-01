# Mistral Provider Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Mistral as a first-class LLM provider for the agent loop, reusing the OpenAI-compatible client with `baseUrl: https://api.mistral.ai`, and add a model lister adapter that fetches available models from Mistral's `/v1/models` endpoint.

**Architecture:** Mistral's API is OpenAI-compatible (same `/v1/chat/completions`, same SSE streaming, same tool_calls format). We add `LlmProvider.mistral` as a new enum value and instantiate `OpenAiClient` with `baseUrl: 'https://api.mistral.ai'` in the factory — no new client class needed. A `mistralApiKey` field on `GlueConfig` is shared with the existing OCR usage (same `MISTRAL_API_KEY` env var). Curated model entries for Mistral Large, Small, Medium, and Codestral are added to the registry.

**Tech Stack:** Dart 3.4+, existing `OpenAiClient` (reused), existing `LlmClientFactory`, `ModelRegistry`, `ModelLister`, `GlueConfig` patterns.

**Key insight:** Mistral's `/v1/chat/completions` uses the exact same request/response format as OpenAI — messages, tools, tool_choice, streaming SSE with `delta.tool_calls[*].index/function.arguments`, and `finish_reason`. The `/v1/models` endpoint also returns the same `{data: [{id, ...}]}` format. This means zero new protocol code.

**Files touched across all tasks:**

- `cli/lib/src/config/glue_config.dart` (add `mistralApiKey` field, update enum, switches)
- `cli/lib/src/config/model_registry.dart` (add Mistral models, update availability)
- `cli/lib/src/llm/llm_factory.dart` (add mistral case)
- `cli/lib/src/llm/model_lister.dart` (add `_listMistral`)
- `cli/lib/src/agent/agent_manager.dart` (update apiKey switch)
- `cli/lib/glue.dart` (barrel export if needed)
- Tests for all of the above

---

## Task 1: Add `LlmProvider.mistral` enum value

**Files:**

- Modify: `cli/lib/src/config/glue_config.dart`

**Step 1: Add `mistral` to the `LlmProvider` enum**

In `cli/lib/src/config/glue_config.dart`, change:

```dart
enum LlmProvider { anthropic, openai, ollama }
```

to:

```dart
enum LlmProvider { anthropic, openai, mistral, ollama }
```

**Step 2: Run analyze to find all broken switches**

Run: `cd cli && dart analyze 2>&1 | grep -i "switch\|missing\|exhaustive\|mistral"`
Expected: multiple errors about non-exhaustive switches — this is expected and will be fixed in subsequent tasks.

**Step 3: Commit**

```bash
git add cli/lib/src/config/glue_config.dart
git commit -m "feat(mistral): add LlmProvider.mistral enum value"
```

---

## Task 2: Add `mistralApiKey` to `GlueConfig` + fix exhaustive switches

**Files:**

- Modify: `cli/lib/src/config/glue_config.dart`

**Step 1: Add `mistralApiKey` field to `GlueConfig`**

Add to the class fields (after `openaiApiKey`):

```dart
final String? mistralApiKey;
```

Add to constructor parameters (after `this.openaiApiKey`):

```dart
this.mistralApiKey,
```

**Step 2: Update `copyWith` to include `mistralApiKey`**

```dart
GlueConfig copyWith({
  LlmProvider? provider,
  String? model,
  ObservabilityConfig? observability,
}) {
  return GlueConfig(
    // ... existing fields ...
    mistralApiKey: mistralApiKey,
    // ...
  );
}
```

**Step 3: Update `validate()` to handle `mistral`**

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
String get apiKey {
  if (provider == LlmProvider.ollama) return '';
  validate();
  return switch (provider) {
    LlmProvider.anthropic => anthropicApiKey!,
    LlmProvider.openai => openaiApiKey!,
    LlmProvider.mistral => mistralApiKey!,
    LlmProvider.ollama => '',
  };
}
```

**Step 5: Wire `mistralApiKey` in `GlueConfig.load()`**

After the `openaiKey` resolution block, add:

```dart
final mistralKey = Platform.environment['MISTRAL_API_KEY'] ??
    Platform.environment['GLUE_MISTRAL_API_KEY'] ??
    (fileConfig?['mistral'] as Map?)?['api_key'] as String?;
```

And pass `mistralApiKey: mistralKey` to the `GlueConfig(...)` constructor call.

Note: The existing `mistralApiKey` variable in section 2e (PDF config) reads from the same `MISTRAL_API_KEY` env var. This is intentional — one API key serves both LLM and OCR usage.

**Step 6: Run analyze**

Run: `cd cli && dart analyze`
Expected: remaining errors only in `llm_factory.dart`, `model_lister.dart`, `agent_manager.dart` (fixed in later tasks)

**Step 7: Commit**

```bash
git add cli/lib/src/config/glue_config.dart
git commit -m "feat(mistral): add mistralApiKey to GlueConfig with env/yaml resolution"
```

---

## Task 3: Add Mistral to `LlmClientFactory`

**Files:**

- Modify: `cli/lib/src/llm/llm_factory.dart`

**Step 1: Add `mistral` case to `create()` method**

```dart
LlmProvider.mistral => OpenAiClient(
    httpClient: _httpClient,
    apiKey: apiKey,
    model: model,
    systemPrompt: systemPrompt,
    baseUrl: 'https://api.mistral.ai',
  ),
```

**Step 2: Add `mistral` case to `createFromEntry()` apiKey switch**

```dart
LlmProvider.mistral => config.mistralApiKey ?? '',
```

**Step 3: Add `mistral` case to `createFromProfile()` apiKey switch**

```dart
LlmProvider.mistral => config.mistralApiKey ?? '',
```

**Step 4: Run analyze**

Run: `cd cli && dart analyze`
Expected: remaining errors only in `model_lister.dart`, `agent_manager.dart`

**Step 5: Commit**

```bash
git add cli/lib/src/llm/llm_factory.dart
git commit -m "feat(mistral): wire Mistral into LlmClientFactory via OpenAiClient"
```

---

## Task 4: Add Mistral to `ModelLister`

**Files:**

- Modify: `cli/lib/src/llm/model_lister.dart`
- Test: `cli/test/llm/model_lister_test.dart` (if exists, extend)

**Step 1: Add `_listMistral` method**

```dart
Future<List<ModelInfo>> _listMistral(String apiKey) async {
  final uri = Uri.parse('https://api.mistral.ai/v1/models');
  final response = await _http.get(uri, headers: {
    'Authorization': 'Bearer $apiKey',
  }).timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw Exception('Mistral API error ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final data = json['data'] as List? ?? [];
  final models = data
      .map((m) {
        final map = m as Map<String, dynamic>;
        return ModelInfo(id: map['id'] as String? ?? '');
      })
      .where((m) => m.id.isNotEmpty)
      .toList();
  models.sort((a, b) => a.id.compareTo(b.id));
  return models;
}
```

**Step 2: Add `mistral` case to `list()` switch**

```dart
LlmProvider.mistral => _listMistral(apiKey ?? ''),
```

**Step 3: Run analyze**

Run: `cd cli && dart analyze`
Expected: remaining errors only in `agent_manager.dart`

**Step 4: Commit**

```bash
git add cli/lib/src/llm/model_lister.dart
git commit -m "feat(mistral): add Mistral model lister using /v1/models"
```

---

## Task 5: Add Mistral to `ModelRegistry`

**Files:**

- Modify: `cli/lib/src/config/model_registry.dart`
- Test: `cli/test/config/model_registry_test.dart` (extend)

**Step 1: Add curated Mistral models**

Add after the Ollama section in the `models` list:

```dart
    // ── Mistral ────────────────────────────────────────────────
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
      displayName: 'Mistral Medium',
      modelId: 'mistral-medium-latest',
      provider: LlmProvider.mistral,
      capabilities: {ModelCapability.coding, ModelCapability.reasoning},
      cost: CostTier.medium,
      speed: SpeedTier.standard,
      tagline: 'Balanced performance',
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

**Step 2: Update `available()` to check Mistral API key**

Add to the switch inside `available()`:

```dart
LlmProvider.mistral =>
  config.mistralApiKey != null && config.mistralApiKey!.isNotEmpty,
```

**Step 3: Write tests**

Add to `cli/test/config/model_registry_test.dart`:

```dart
  test('contains Mistral models', () {
    final mistral = ModelRegistry.forProvider(LlmProvider.mistral);
    expect(mistral.length, greaterThanOrEqualTo(3));
    expect(mistral.any((m) => m.modelId == 'mistral-large-latest'), isTrue);
  });

  test('Mistral has a default model', () {
    final def = ModelRegistry.defaultFor(LlmProvider.mistral);
    expect(def.modelId, 'mistral-large-latest');
  });
```

**Step 4: Run tests**

Run: `cd cli && dart test test/config/model_registry_test.dart`
Expected: all pass

**Step 5: Commit**

```bash
git add cli/lib/src/config/model_registry.dart cli/test/config/model_registry_test.dart
git commit -m "feat(mistral): add curated Mistral models to registry"
```

---

## Task 6: Fix remaining exhaustive switches

**Files:**

- Modify: `cli/lib/src/agent/agent_manager.dart`

**Step 1: Add `mistral` case to `AgentManager` apiKey switch**

Find the switch on `profile.provider` and add:

```dart
LlmProvider.mistral => config.mistralApiKey ?? '',
```

**Step 2: Run full analyze**

Run: `cd cli && dart analyze`
Expected: zero new warnings/errors (only pre-existing info-level issues)

**Step 3: Commit**

```bash
git add cli/lib/src/agent/agent_manager.dart
git commit -m "feat(mistral): fix remaining exhaustive switches for LlmProvider.mistral"
```

---

## Task 7: Write integration tests

**Files:**

- Create: `cli/test/llm/mistral_client_test.dart`

**Step 1: Write tests for Mistral factory wiring**

```dart
import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/llm/openai_client.dart';

void main() {
  group('Mistral via LlmClientFactory', () {
    test('creates OpenAiClient for mistral provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.mistral,
        model: 'mistral-large-latest',
        apiKey: 'test-key',
        systemPrompt: 'You are helpful.',
      );
      expect(client, isA<OpenAiClient>());
    });

    test('GlueConfig validates mistral API key', () {
      final config = GlueConfig(
        provider: LlmProvider.mistral,
        model: 'mistral-large-latest',
        mistralApiKey: 'test-key',
      );
      expect(() => config.validate(), returnsNormally);
    });

    test('GlueConfig rejects missing mistral API key', () {
      final config = GlueConfig(
        provider: LlmProvider.mistral,
        model: 'mistral-large-latest',
      );
      expect(() => config.validate(), throwsA(isA<ConfigError>()));
    });

    test('apiKey getter returns mistral key', () {
      final config = GlueConfig(
        provider: LlmProvider.mistral,
        model: 'mistral-large-latest',
        mistralApiKey: 'mk-test',
      );
      expect(config.apiKey, 'mk-test');
    });
  });
}
```

**Step 2: Run tests**

Run: `cd cli && dart test test/llm/mistral_client_test.dart`
Expected: all pass

**Step 3: Run full test suite**

Run: `cd cli && dart test`
Expected: all tests pass, no regressions

**Step 4: Commit**

```bash
git add cli/test/llm/mistral_client_test.dart
git commit -m "test(mistral): add Mistral provider integration tests"
```

---

## Task 8: Final verification

**Step 1: Run full test suite**

Run: `cd cli && dart test`
Expected: all pass

**Step 2: Run analyzer**

Run: `cd cli && dart analyze`
Expected: zero new warnings

**Step 3: Manual smoke test (if MISTRAL_API_KEY available)**

```bash
cd cli
MISTRAL_API_KEY=your-key dart run bin/glue.dart --provider mistral --model mistral-small-latest
```

Type: "What is 2+2?" — verify streaming response works.
Type: "Read the file README.md" — verify tool calling works.

**Step 4: Final commit**

No code changes — just verify everything works.
