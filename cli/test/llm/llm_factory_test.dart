import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/providers/anthropic_provider.dart';
import 'package:glue/src/providers/ollama_provider.dart';
import 'package:glue/src/providers/openai_provider.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

void main() {
  group('LlmClientFactory.createFor', () {
    test('returns AnthropicProvider for anthropic/<model>', () {
      final config = testConfig(
        env: {'ANTHROPIC_API_KEY': 'sk-anthropic'},
      );
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('anthropic/claude-sonnet-4.6'),
        systemPrompt: 'test',
      );
      expect(client, isA<AnthropicProvider>());
    });

    test('returns OpenAiProvider for openai/<model>', () {
      final config = testConfig(env: {'OPENAI_API_KEY': 'sk-openai'});
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('openai/gpt-5.4'),
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiProvider>());
    });

    test('returns OpenAiProvider for groq/gpt-oss-120b', () {
      final config = testConfig(env: {'GROQ_API_KEY': 'sk-groq'});
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('groq/gpt-oss-120b'),
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiProvider>());
    });

    test('returns OllamaProvider for ollama (native adapter, api_key: none)',
        () {
      final config = testConfig();
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('ollama/qwen2.5-coder:32b'),
        systemPrompt: 'test',
      );
      expect(client, isA<OllamaProvider>());
    });

    test('unknown provider throws ConfigError', () {
      final config = testConfig();
      final factory = LlmClientFactory(config);
      expect(
        () => factory.createFor(
          ModelRef.parse('nope/whatever'),
          systemPrompt: '',
        ),
        throwsA(isA<ConfigError>()),
      );
    });
  });
}
