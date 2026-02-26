import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';

void main() {
  group('GlueConfig', () {
    test('resolves provider and model from explicit values', () {
      final config = GlueConfig(
        provider: LlmProvider.anthropic,
        model: 'claude-sonnet-4-6',
        anthropicApiKey: 'sk-ant-test',
      );
      expect(config.provider, LlmProvider.anthropic);
      expect(config.model, 'claude-sonnet-4-6');
      expect(config.anthropicApiKey, 'sk-ant-test');
    });

    test('defaults to anthropic/claude-sonnet-4-6', () {
      final config = GlueConfig(anthropicApiKey: 'sk-ant-test');
      expect(config.provider, LlmProvider.anthropic);
      expect(config.model, 'claude-sonnet-4-6');
    });

    test('resolves openai provider', () {
      final config = GlueConfig(
        provider: LlmProvider.openai,
        model: 'gpt-4.1',
        openaiApiKey: 'sk-test',
      );
      expect(config.provider, LlmProvider.openai);
      expect(config.model, 'gpt-4.1');
    });

    test('resolves ollama provider (no API key needed)', () {
      final config = GlueConfig(
        provider: LlmProvider.ollama,
        model: 'qwen2.5-coder',
      );
      expect(config.provider, LlmProvider.ollama);
      expect(config.model, 'qwen2.5-coder');
      config.validate(); // Should not throw
    });

    test('validates API key presence', () {
      expect(
        () => GlueConfig(provider: LlmProvider.anthropic).validate(),
        throwsA(isA<ConfigError>()),
      );
    });

    test('profiles override defaults', () {
      final config = GlueConfig(
        anthropicApiKey: 'sk-ant',
        openaiApiKey: 'sk-oai',
        profiles: {
          'architect': AgentProfile(provider: LlmProvider.anthropic, model: 'claude-opus-4-6'),
          'editor': AgentProfile(provider: LlmProvider.openai, model: 'gpt-4.1-mini'),
          'local': AgentProfile(provider: LlmProvider.ollama, model: 'qwen2.5-coder'),
        },
      );
      expect(config.profiles['architect']!.model, 'claude-opus-4-6');
      expect(config.profiles['editor']!.provider, LlmProvider.openai);
      expect(config.profiles['local']!.provider, LlmProvider.ollama);
    });
  });
}
