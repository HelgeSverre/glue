import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  group('ModelRegistry', () {
    test('findById returns correct entry', () {
      final entry = ModelRegistry.findById('claude-sonnet-4-6');
      expect(entry, isNotNull);
      expect(entry!.displayName, 'Claude Sonnet 4.6');
      expect(entry.provider, LlmProvider.anthropic);
    });

    test('findById returns null for unknown model', () {
      expect(ModelRegistry.findById('nonexistent-model'), isNull);
    });

    test('findByName matches by modelId', () {
      final entry = ModelRegistry.findByName('gpt-4.1');
      expect(entry, isNotNull);
      expect(entry!.displayName, 'GPT-4.1');
    });

    test('findByName matches by displayName', () {
      final entry = ModelRegistry.findByName('Claude Opus 4.6');
      expect(entry, isNotNull);
      expect(entry!.modelId, 'claude-opus-4-6');
    });

    test('findByName matches by substring', () {
      final entry = ModelRegistry.findByName('opus');
      expect(entry, isNotNull);
      expect(entry!.modelId, 'claude-opus-4-6');
    });

    test('findByName is case-insensitive', () {
      final entry = ModelRegistry.findByName('HAIKU');
      expect(entry, isNotNull);
      expect(entry!.modelId, 'claude-haiku-3-5');
    });

    test('findByName returns null for no match', () {
      expect(ModelRegistry.findByName('nonexistent'), isNull);
    });

    test('forProvider filters correctly', () {
      final anthropic = ModelRegistry.forProvider(LlmProvider.anthropic);
      expect(anthropic, isNotEmpty);
      expect(anthropic.every((m) => m.provider == LlmProvider.anthropic), isTrue);

      final openai = ModelRegistry.forProvider(LlmProvider.openai);
      expect(openai, isNotEmpty);
      expect(openai.every((m) => m.provider == LlmProvider.openai), isTrue);

      final ollama = ModelRegistry.forProvider(LlmProvider.ollama);
      expect(ollama, isNotEmpty);
      expect(ollama.every((m) => m.provider == LlmProvider.ollama), isTrue);
    });

    test('available filters by configured API keys', () {
      final configAnthropicOnly = GlueConfig(
        anthropicApiKey: 'sk-test',
        openaiApiKey: null,
      );
      final available = ModelRegistry.available(configAnthropicOnly);
      // Should include anthropic + ollama, not openai.
      expect(
        available.any((m) => m.provider == LlmProvider.anthropic),
        isTrue,
      );
      expect(
        available.any((m) => m.provider == LlmProvider.ollama),
        isTrue,
      );
      expect(
        available.any((m) => m.provider == LlmProvider.openai),
        isFalse,
      );
    });

    test('available includes ollama always', () {
      final configNoKeys = GlueConfig();
      final available = ModelRegistry.available(configNoKeys);
      expect(
        available.any((m) => m.provider == LlmProvider.ollama),
        isTrue,
      );
    });

    test('available includes all providers when both keys set', () {
      final configBoth = GlueConfig(
        anthropicApiKey: 'sk-ant',
        openaiApiKey: 'sk-oai',
      );
      final available = ModelRegistry.available(configBoth);
      final providers = available.map((m) => m.provider).toSet();
      expect(providers, containsAll(LlmProvider.values));
    });

    test('withCapability filters correctly', () {
      final fast = ModelRegistry.withCapability(ModelCapability.fast);
      expect(fast, isNotEmpty);
      expect(fast.every((m) => m.capabilities.contains(ModelCapability.fast)),
          isTrue);

      final reasoning = ModelRegistry.withCapability(ModelCapability.reasoning);
      expect(reasoning, isNotEmpty);
      expect(
          reasoning
              .every((m) => m.capabilities.contains(ModelCapability.reasoning)),
          isTrue);
    });

    test('every entry has a unique modelId', () {
      final ids = ModelRegistry.models.map((m) => m.modelId).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'All model IDs must be unique');
    });

    test('every provider has exactly one default', () {
      for (final provider in LlmProvider.values) {
        final defaults = ModelRegistry.models
            .where((m) => m.provider == provider && m.isDefault)
            .toList();
        expect(defaults, hasLength(1),
            reason: '${provider.name} should have exactly one default');
      }
    });

    test('defaultFor returns the default entry', () {
      final entry = ModelRegistry.defaultFor(LlmProvider.anthropic);
      expect(entry.isDefault, isTrue);
      expect(entry.provider, LlmProvider.anthropic);
      expect(entry.modelId, 'claude-sonnet-4-6');
    });

    test('defaultModelId matches defaultFor entry', () {
      for (final provider in LlmProvider.values) {
        final id = ModelRegistry.defaultModelId(provider);
        final entry = ModelRegistry.defaultFor(provider);
        expect(id, entry.modelId);
      }
    });

    test('costLabel returns expected values', () {
      final free = ModelRegistry.findById('llama3.2');
      expect(free!.costLabel, 'free');

      final premium = ModelRegistry.findById('claude-opus-4-6');
      expect(premium!.costLabel, r'$$$$');
    });

    test('speedLabel returns expected values', () {
      final fast = ModelRegistry.findById('claude-haiku-3-5');
      expect(fast!.speed, SpeedTier.fast);
      expect(fast.speedLabel, contains('\u25cf'));

      final slow = ModelRegistry.findById('claude-opus-4-6');
      expect(slow!.speed, SpeedTier.slow);
    });
  });
}
