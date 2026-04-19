import 'dart:convert';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/tools/subagent_tools.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

class _EchoLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final last = messages.lastWhere((m) => m.role == Role.user);
    yield TextDelta('Done: ${last.text}');
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

class _EchoFactory implements LlmClientFactory {
  @override
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) =>
      _EchoLlm();

  @override
  LlmClient createFromConfig({required String systemPrompt}) => _EchoLlm();
}

void main() {
  late AgentManager manager;

  setUp(() {
    manager = AgentManager(
      tools: {},
      llmFactory: _EchoFactory(),
      config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
      systemPrompt: 'test',
    );
  });

  group('SpawnSubagentTool', () {
    test('has correct schema', () {
      final tool = SpawnSubagentTool(manager);
      expect(tool.name, 'spawn_subagent');
      expect(tool.parameters.any((p) => p.name == 'task'), isTrue);
      expect(tool.parameters.any((p) => p.name == 'model_ref'), isTrue);
      expect(
        tool.parameters.any((p) => p.name == 'provider'),
        isFalse,
        reason: 'old {provider, model} schema is gone',
      );
    });

    test('executes and returns result', () async {
      final tool = SpawnSubagentTool(manager);
      final result = ContentPart.textOnly(
        await tool.execute({'task': 'Write tests'}),
      );
      expect(result, contains('Done: Write tests'));
    });

    test('accepts model_ref override', () async {
      final tool = SpawnSubagentTool(manager);
      final result = ContentPart.textOnly(
        await tool.execute({
          'task': 'quick task',
          'model_ref': 'anthropic/claude-haiku-4.5',
        }),
      );
      expect(result, contains('Done:'));
    });
  });

  group('SpawnParallelSubagentsTool', () {
    test('has correct schema', () {
      final tool = SpawnParallelSubagentsTool(manager);
      expect(tool.name, 'spawn_parallel_subagents');
      expect(tool.parameters.any((p) => p.name == 'tasks'), isTrue);
      expect(tool.parameters.any((p) => p.name == 'model_ref'), isTrue);
    });

    test('executes parallel tasks', () async {
      final tool = SpawnParallelSubagentsTool(manager);
      final result = ContentPart.textOnly(
        await tool.execute({
          'tasks': ['Task A', 'Task B'],
        }),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final results = decoded['results'] as List;
      expect(results, hasLength(2));
    });
  });
}
