import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/anthropic_client.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/llm/openai_client.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

void main() {
  group('LlmClientFactory.createFor', () {
    test('returns AnthropicClient for anthropic/<model>', () {
      final config = testConfig(
        env: {'ANTHROPIC_API_KEY': 'sk-anthropic'},
      );
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('anthropic/claude-sonnet-4.6'),
        systemPrompt: 'test',
      );
      expect(client, isA<AnthropicClient>());
    });

    test('returns OpenAiClient for openai/<model>', () {
      final config = testConfig(env: {'OPENAI_API_KEY': 'sk-openai'});
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('openai/gpt-5.4'),
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiClient>());
    });

    test('returns OpenAiClient for groq/qwen/qwen3-coder (slash in model id)',
        () {
      final config = testConfig(env: {'GROQ_API_KEY': 'sk-groq'});
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('groq/qwen/qwen3-coder'),
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiClient>());
    });

    test('returns OpenAiClient for ollama (api_key: none)', () {
      final config = testConfig();
      final factory = LlmClientFactory(config);
      final client = factory.createFor(
        ModelRef.parse('ollama/qwen2.5-coder:32b'),
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiClient>());
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
