import 'package:glue_harness/glue_harness.dart';
import 'package:glue_core/glue_core.dart';
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

    test('emits subagent_spawned/event/completed via onPersistEvent', () async {
      final persisted = <Map<String, dynamic>>[];
      manager.onPersistEvent = (type, data) {
        persisted.add({'type': type, ...data});
      };

      await manager.spawnSubagent(task: 'verify persistence');

      expect(persisted.first['type'], 'subagent_spawned');
      expect(persisted.first['task'], 'verify persistence');
      expect(persisted.first['subagent_id'], isA<String>());
      final subagentId = persisted.first['subagent_id'];

      expect(persisted.last['type'], 'subagent_completed');
      expect(persisted.last['subagent_id'], subagentId);
      expect(persisted.last.containsKey('error'), isFalse);

      // All inner events carry the same subagent_id and a serialised inner.
      final innerEvents =
          persisted.where((e) => e['type'] == 'subagent_event').toList();
      expect(innerEvents, isNotEmpty);
      for (final e in innerEvents) {
        expect(e['subagent_id'], subagentId);
        expect(e['inner'], isA<Map<String, dynamic>>());
      }
    });

    test('parallel spawns produce distinct subagent ids', () async {
      final ids = <String>{};
      manager.onPersistEvent = (type, data) {
        if (type == 'subagent_spawned') {
          ids.add(data['subagent_id'] as String);
        }
      };

      await manager.spawnParallel(tasks: ['A', 'B', 'C']);

      expect(ids, hasLength(3));
    });

    test('always emits subagent_completed even when the LLM errors', () async {
      // AgentRunner internally captures provider errors and returns a string
      // result rather than rethrowing, so this test asserts the persistence
      // pipe fires its terminal event regardless of how the runner finishes.
      final failingManager = AgentManager(
        tools: const {},
        llmFactory: _ThrowingFactory(),
        config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
        systemPrompt: 'unused',
      );
      final persisted = <Map<String, dynamic>>[];
      failingManager.onPersistEvent =
          (type, data) => persisted.add({'type': type, ...data});

      await failingManager.spawnSubagent(task: 'will fail');

      expect(persisted.first['type'], 'subagent_spawned');
      expect(persisted.last['type'], 'subagent_completed');
    });
  });
}

class _ThrowingFactory implements LlmClientFactory {
  @override
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) =>
      _ThrowingLlm();

  @override
  LlmClient createFromConfig({required String systemPrompt}) => _ThrowingLlm();
}

class _ThrowingLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    throw Exception('boom');
  }
}
