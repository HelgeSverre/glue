import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/agent_manager.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

class _EchoLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final lastMsg = messages.lastWhere((m) => m.role == Role.user);
    yield TextDelta('Processed: ${lastMsg.text}');
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
  group('AgentManager', () {
    late AgentManager manager;

    setUp(() {
      manager = AgentManager(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _EchoFactory(),
        config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
        systemPrompt: 'You are a test agent.',
      );
    });

    test('spawns a single subagent', () async {
      final result = await manager.spawnSubagent(task: 'Do something');
      expect(result, contains('Processed:'));
      expect(result, contains('Do something'));
    });

    test('spawns parallel subagents', () async {
      final results = await manager.spawnParallel(
        tasks: ['Task A', 'Task B', 'Task C'],
      );
      expect(results, hasLength(3));
      expect(results[0], contains('Task A'));
      expect(results[1], contains('Task B'));
      expect(results[2], contains('Task C'));
    });

    test('enforces max depth', () async {
      expect(
        () => manager.spawnSubagent(task: 'deep', currentDepth: 3),
        throwsA(isA<Exception>()),
      );
    });
  });
}
