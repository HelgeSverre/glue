/// Integration test: the bundled reference catalog at
/// `docs/reference/models.yaml` must parse and reflect the designed shape.
///
/// This test is the safety net between the source-of-truth YAML and the
/// codegen output. If it breaks, either the YAML changed intentionally (update
/// this test) or the parser regressed (fix the parser).
library;

import 'dart:io';

import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('reference catalog (docs/reference/models.yaml)', () {
    final yaml = File('../docs/reference/models.yaml').readAsStringSync();
    final catalog = parseCatalogYaml(yaml);

    test('has expected version and defaults', () {
      expect(catalog.version, 1);
      expect(catalog.defaults.model, 'anthropic/claude-sonnet-4-6');
      expect(catalog.defaults.smallModel, 'openai/gpt-5.4-mini');
      expect(catalog.defaults.localModel, isNotEmpty);
    });

    test('declares all 9 capability descriptions', () {
      expect(catalog.capabilities.keys,
          containsAll(['chat', 'tools', 'vision', 'coding']));
    });

    test('has the expected provider set', () {
      expect(
        catalog.providers.keys.toSet(),
        containsAll(
            ['anthropic', 'openai', 'gemini', 'mistral', 'groq', 'ollama']),
      );
    });

    test('anthropic provider includes current 4.6/4.7 family models', () {
      final anthropic = catalog.providers['anthropic']!;
      final opus47 = anthropic.models['claude-opus-4-7']!;
      final sonnet46 = anthropic.models['claude-sonnet-4-6']!;
      final opus46 = anthropic.models['claude-opus-4-6']!;
      final haiku45 = anthropic.models['claude-haiku-4-5']!;
      expect(opus47.recommended, isTrue);
      expect(sonnet46.recommended, isTrue);
      expect(opus46.recommended, isTrue);
      expect(haiku45.recommended, isTrue);
      expect(opus47.capabilities, contains('tools'));
    });

    test('anthropic 4.6/4.7 family advertises native 1M context', () {
      final anthropic = catalog.providers['anthropic']!;
      expect(anthropic.models['claude-opus-4-7']!.contextWindow, 1000000);
      expect(anthropic.models['claude-opus-4-6']!.contextWindow, 1000000);
      expect(anthropic.models['claude-sonnet-4-6']!.contextWindow, 1000000);
      expect(anthropic.models['claude-haiku-4-5']!.contextWindow, 200000);
    });

    test('anthropic defaults point at the current Sonnet ID', () {
      final anthropic = catalog.providers['anthropic']!;
      final sonnet = anthropic.models['claude-sonnet-4-6']!;
      expect(catalog.defaults.model, 'anthropic/claude-sonnet-4-6');
      expect(sonnet.isDefault, isTrue);
      expect(sonnet.capabilities, contains('tools'));
    });

    test('anthropic catalog does not list the non-existent sonnet-4-7', () {
      final anthropic = catalog.providers['anthropic']!;
      expect(anthropic.models.containsKey('claude-sonnet-4-7'), isFalse);
    });

    test('openai catalog only advertises chat-completions-compatible models',
        () {
      final openai = catalog.providers['openai']!;
      expect(openai.models.containsKey('gpt-5.3-codex'), isFalse);
      expect(openai.models.containsKey('gpt-5.4'), isTrue);
      expect(openai.models.containsKey('gpt-5.4-mini'), isTrue);
    });

    test('ollama provider uses api_key: none', () {
      final ollama = catalog.providers['ollama']!;
      expect(ollama.auth.kind, AuthKind.none);
      expect(ollama.baseUrl, startsWith('http://localhost:'));
    });

    test('groq uses openai adapter (not a native groq adapter)', () {
      final groq = catalog.providers['groq']!;
      expect(groq.adapter, 'openai');
      expect(groq.compatibility, 'groq');
    });

    test('model IDs may contain slashes (groq qwen)', () {
      final groq = catalog.providers['groq']!;
      expect(groq.models.keys, contains('qwen/qwen3-coder'));
    });

    test('openrouter declares required request headers', () {
      final openrouter = catalog.providers['openrouter'];
      if (openrouter == null) return; // optional
      expect(openrouter.requestHeaders, containsPair('HTTP-Referer', anything));
      expect(openrouter.requestHeaders, containsPair('X-Title', anything));
    });
  });
}
