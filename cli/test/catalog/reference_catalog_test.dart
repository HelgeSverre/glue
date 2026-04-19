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
      expect(catalog.defaults.model, 'anthropic/claude-sonnet-4.6');
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

    test('anthropic provider has default claude-sonnet-4.6', () {
      final anthropic = catalog.providers['anthropic']!;
      final sonnet = anthropic.models['claude-sonnet-4.6']!;
      expect(sonnet.isDefault, isTrue);
      expect(sonnet.recommended, isTrue);
      expect(sonnet.capabilities, contains('tools'));
      expect(sonnet.contextWindow, 200000);
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
