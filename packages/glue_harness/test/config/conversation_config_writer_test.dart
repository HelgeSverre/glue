import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory tempDir;
  late String configPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'conversation_config_writer_test_',
    );
    configPath = '${tempDir.path}/config.yaml';
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('creates config and writes the effective model and reasoning', () {
    ConversationConfigWriter(configPath).setModelAndReasoning(
      const ModelRef(providerId: 'openai', modelId: 'o3'),
      const ReasoningConfig(effort: ReasoningEffort.high, showThoughts: true),
    );

    final yaml = loadYaml(File(configPath).readAsStringSync()) as Map;
    expect(yaml['active_model'], 'openai/o3');
    expect((yaml['reasoning'] as Map)['effort'], 'high');
    expect((yaml['reasoning'] as Map)['show_thoughts'], isTrue);
  });

  test('bootstraps an existing empty config', () {
    File(configPath).writeAsStringSync('');

    ConversationConfigWriter(
      configPath,
    ).setReasoning(const ReasoningConfig(effort: ReasoningEffort.medium));

    final yaml = loadYaml(File(configPath).readAsStringSync()) as Map;
    expect((yaml['reasoning'] as Map)['effort'], 'medium');
  });

  test('bootstraps a comments-only config without losing comments', () {
    File(configPath).writeAsStringSync('''# managed by dotfiles
# keep this note
''');

    ConversationConfigWriter(configPath).setModelAndReasoning(
      ModelRef.parse('anthropic/claude-sonnet-5'),
      const ReasoningConfig(effort: ReasoningEffort.high),
    );

    final contents = File(configPath).readAsStringSync();
    final yaml = loadYaml(contents) as Map;
    expect(contents, contains('# managed by dotfiles'));
    expect(contents, contains('# keep this note'));
    expect(yaml['active_model'], 'anthropic/claude-sonnet-5');
    expect((yaml['reasoning'] as Map)['effort'], 'high');
  });

  test(
    'reasoning-only update preserves model, comments, and unrelated keys',
    () {
      File(configPath).writeAsStringSync('''# keep this comment
active_model: anthropic/claude-sonnet-4-6
custom_key: keep-me
reasoning:
  effort: low # effort comment
  show_thoughts: false
''');

      ConversationConfigWriter(configPath).setReasoning(
        const ReasoningConfig(
          effort: ReasoningEffort.xhigh,
          showThoughts: true,
        ),
      );

      final contents = File(configPath).readAsStringSync();
      final yaml = loadYaml(contents) as Map;
      expect(contents, contains('# keep this comment'));
      expect(contents, contains('# effort comment'));
      expect(yaml['active_model'], 'anthropic/claude-sonnet-4-6');
      expect(yaml['custom_key'], 'keep-me');
      expect((yaml['reasoning'] as Map)['effort'], 'xhigh');
      expect((yaml['reasoning'] as Map)['show_thoughts'], isTrue);
    },
  );

  test('invalid source is not replaced', () {
    const original = 'reasoning: [unterminated';
    File(configPath).writeAsStringSync(original);

    expect(
      () => ConversationConfigWriter(
        configPath,
      ).setReasoning(const ReasoningConfig(effort: ReasoningEffort.high)),
      throwsA(isA<ConversationConfigWriteError>()),
    );
    expect(File(configPath).readAsStringSync(), original);
  });

  test('updates a symlink target without replacing the symlink', () {
    if (Platform.isWindows) return;
    final targetPath = '${tempDir.path}/dotfiles/glue.yaml';
    File(targetPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('active_model: anthropic/claude-sonnet-4-6\n');
    Link(configPath).createSync('dotfiles/glue.yaml');

    ConversationConfigWriter(configPath).setReasoning(
      const ReasoningConfig(effort: ReasoningEffort.high, showThoughts: true),
    );

    expect(
      FileSystemEntity.typeSync(configPath, followLinks: false),
      FileSystemEntityType.link,
    );
    final yaml = loadYaml(File(targetPath).readAsStringSync()) as Map;
    expect((yaml['reasoning'] as Map)['effort'], 'high');
    expect((yaml['reasoning'] as Map)['show_thoughts'], isTrue);
  });
}
