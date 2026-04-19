import 'dart:io';

import 'package:glue/src/core/environment.dart';
import 'package:test/test.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/approval_mode.dart';

void main() {
  group('GlueConfig', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('glue_config_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

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

    test('copyWith preserves titleModel, skillPaths, and approvalMode', () {
      final config = GlueConfig(
        provider: LlmProvider.anthropic,
        model: 'claude-sonnet-4-6',
        anthropicApiKey: 'sk-ant-test',
        titleModel: 'claude-haiku-4',
        skillPaths: const ['/opt/skills', '~/skills'],
        approvalMode: ApprovalMode.auto,
      );

      final copied = config.copyWith(model: 'claude-opus-4-6');
      expect(copied.titleModel, 'claude-haiku-4');
      expect(copied.skillPaths, ['/opt/skills', '~/skills']);
      expect(copied.approvalMode, ApprovalMode.auto);
    });

    test('load uses injected environment home for config.yaml', () {
      final glueDir = Directory('${tempDir.path}/.glue')..createSync();
      final configFile = File('${glueDir.path}/config.yaml');
      configFile.writeAsStringSync('''
provider: openai
model: gpt-4.1-mini
openai:
  api_key: sk-open-file
approval_mode: auto
skills:
  paths:
    - /opt/skills
''');

      final environment =
          Environment.test(home: tempDir.path, cwd: tempDir.path);
      final config = GlueConfig.load(environment: environment);

      expect(config.provider, LlmProvider.openai);
      expect(config.model, 'gpt-4.1-mini');
      expect(config.openaiApiKey, 'sk-open-file');
      expect(config.approvalMode, ApprovalMode.auto);
      expect(config.skillPaths, ['/opt/skills']);
    });

    test('load ignores stale interaction_mode key without crashing', () {
      final glueDir = Directory('${tempDir.path}/.glue')..createSync();
      final configFile = File('${glueDir.path}/config.yaml');
      configFile.writeAsStringSync('''
provider: openai
model: gpt-4.1-mini
openai:
  api_key: sk-open-file
interaction_mode: ask
''');

      final environment =
          Environment.test(home: tempDir.path, cwd: tempDir.path);
      final config = GlueConfig.load(environment: environment);

      expect(config.provider, LlmProvider.openai);
      expect(config.approvalMode, ApprovalMode.confirm);
    });

    test('load parses GLUE_SKILLS_PATHS using injected platform separator', () {
      final environment = Environment.test(
        home: tempDir.path,
        cwd: tempDir.path,
        isWindows: true,
        vars: const {'GLUE_SKILLS_PATHS': r'C:\skills;D:\more-skills'},
      );

      final config = GlueConfig.load(environment: environment);
      expect(config.skillPaths, [r'C:\skills', r'D:\more-skills']);
    });

    test('load honors explicit configPath override', () {
      final customDir = Directory('${tempDir.path}/custom')..createSync();
      final configFile = File('${customDir.path}/config.yaml');
      configFile.writeAsStringSync('''
provider: openai
model: gpt-4.1
openai:
  api_key: sk-explicit
''');

      final environment = Environment.test(
        home: '/does/not/matter',
        cwd: tempDir.path,
      );
      final config = GlueConfig.load(
        environment: environment,
        configPath: configFile.path,
      );

      expect(config.provider, LlmProvider.openai);
      expect(config.model, 'gpt-4.1');
      expect(config.openaiApiKey, 'sk-explicit');
    });

    test('load reads ollama.base_url from config file', () {
      final glueDir = Directory('${tempDir.path}/.glue')..createSync();
      final configFile = File('${glueDir.path}/config.yaml');
      configFile.writeAsStringSync('''
provider: ollama
model: llama3.2
ollama:
  base_url: http://127.0.0.1:11435
''');

      final environment =
          Environment.test(home: tempDir.path, cwd: tempDir.path);
      final config = GlueConfig.load(environment: environment);

      expect(config.provider, LlmProvider.ollama);
      expect(config.ollamaBaseUrl, 'http://127.0.0.1:11435');
    });

    test('OLLAMA_BASE_URL overrides file config', () {
      final glueDir = Directory('${tempDir.path}/.glue')..createSync();
      final configFile = File('${glueDir.path}/config.yaml');
      configFile.writeAsStringSync('''
provider: ollama
model: llama3.2
ollama:
  base_url: http://127.0.0.1:11435
''');

      final environment = Environment.test(
        home: tempDir.path,
        cwd: tempDir.path,
        vars: const {'OLLAMA_BASE_URL': 'http://localhost:22434'},
      );
      final config = GlueConfig.load(environment: environment);
      expect(config.ollamaBaseUrl, 'http://localhost:22434');
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
