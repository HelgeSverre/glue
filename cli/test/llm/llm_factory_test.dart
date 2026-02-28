import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/llm/anthropic_client.dart';
import 'package:glue/src/llm/openai_client.dart';
import 'package:glue/src/llm/ollama_client.dart';

void main() {
  group('LlmClientFactory', () {
    test('creates AnthropicClient for anthropic provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.anthropic,
        model: 'claude-sonnet-4-6',
        apiKey: 'sk-test',
        systemPrompt: 'test',
      );
      expect(client, isA<AnthropicClient>());
    });

    test('creates OpenAiClient for openai provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.openai,
        model: 'gpt-4.1',
        apiKey: 'sk-test',
        systemPrompt: 'test',
      );
      expect(client, isA<OpenAiClient>());
    });

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

    test('creates OllamaClient for ollama provider', () {
      final factory = LlmClientFactory();
      final client = factory.create(
        provider: LlmProvider.ollama,
        model: 'llama3.2',
        apiKey: '',
        systemPrompt: 'test',
      );
      expect(client, isA<OllamaClient>());
    });
  });
}
