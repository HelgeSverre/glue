import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/permission_mode.dart';

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
        () => GlueConfig(
          provider: LlmProvider.mistral,
          model: 'mistral-large-latest',
        ).validate(),
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
          'architect': const AgentProfile(
              provider: LlmProvider.anthropic, model: 'claude-opus-4-6'),
          'editor': const AgentProfile(
              provider: LlmProvider.openai, model: 'gpt-4.1-mini'),
          'local': const AgentProfile(
              provider: LlmProvider.ollama, model: 'qwen2.5-coder'),
        },
      );
      expect(config.profiles['architect']!.model, 'claude-opus-4-6');
      expect(config.profiles['editor']!.provider, LlmProvider.openai);
      expect(config.profiles['local']!.provider, LlmProvider.ollama);
    });

    test('bashMaxLines defaults to 50', () {
      final config = GlueConfig(anthropicApiKey: 'sk-ant-test');
      expect(config.bashMaxLines, 50);
    });

    test('bashMaxLines can be set explicitly', () {
      final config = GlueConfig(
        anthropicApiKey: 'sk-ant-test',
        bashMaxLines: 100,
      );
      expect(config.bashMaxLines, 100);
    });

    test('copyWith preserves titleModel, skillPaths, and permissionMode', () {
      final config = GlueConfig(
        provider: LlmProvider.anthropic,
        model: 'claude-sonnet-4-6',
        anthropicApiKey: 'sk-ant-test',
        titleModel: 'claude-haiku-4',
        skillPaths: const ['/opt/skills', '~/skills'],
        permissionMode: PermissionMode.acceptEdits,
      );

      final copied = config.copyWith(model: 'claude-opus-4-6');
      expect(copied.titleModel, 'claude-haiku-4');
      expect(copied.skillPaths, ['/opt/skills', '~/skills']);
      expect(copied.permissionMode, PermissionMode.acceptEdits);
    });
  });

  group('splitPathList', () {
    test('splits colon-separated paths on Unix', () {
      final paths = splitPathList('~/a:~/b:/opt/c', isWindows: false);
      expect(paths, ['~/a', '~/b', '/opt/c']);
    });

    test('splits semicolon-separated paths on Windows', () {
      final paths = splitPathList(r'C:\skills;D:\more', isWindows: true);
      expect(paths, [r'C:\skills', r'D:\more']);
    });

    test('ignores empty segments', () {
      final paths = splitPathList('~/a::~/b:', isWindows: false);
      expect(paths, ['~/a', '~/b']);
    });

    test('returns empty list for empty string', () {
      expect(splitPathList('', isWindows: false), isEmpty);
    });
  });
}
