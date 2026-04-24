import 'dart:convert';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/subagents.dart';
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
  late Subagents manager;

  setUp(() {
    manager = Subagents(
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
      final result = (await tool.execute({'task': 'Write tests'})).content;
      expect(result, contains('Done: Write tests'));
    });

    test('accepts model_ref override', () async {
      final tool = SpawnSubagentTool(manager);
      final result = (await tool.execute({
        'task': 'quick task',
        'model_ref': 'anthropic/claude-haiku-4-5',
      }))
          .content;
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

    test('tasks parameter declares string items for OpenAI validator', () {
      final tool = SpawnParallelSubagentsTool(manager);
      final tasks = tool.parameters.firstWhere((p) => p.name == 'tasks');
      expect(tasks.type, 'array');
      expect(tasks.items, {'type': 'string'});
    });

    test('executes parallel tasks', () async {
      final tool = SpawnParallelSubagentsTool(manager);
      final result = (await tool.execute({
        'tasks': ['Task A', 'Task B'],
      }))
          .content;
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      final results = decoded['results'] as List;
      expect(results, hasLength(2));
    });
  });
}
