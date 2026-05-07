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

    test(
        'rolls subagent token usage into manager.subagentStats and persists '
        'a subagent_usage event', () async {
      final persisted = <Map<String, dynamic>>[];
      manager.onPersistEvent =
          (type, data) => persisted.add({'type': type, ...data});
      final liveCallbacks = <UsageStats>[];
      manager.onSubagentUsage = liveCallbacks.add;

      await manager.spawnSubagent(task: 'measure tokens');

      // The _EchoLlm yields one UsageInfo(input: 5, output: 5) per turn.
      expect(manager.subagentStats.inputTokens, 5);
      expect(manager.subagentStats.outputTokens, 5);
      expect(manager.subagentStats.turnCount, 1);

      // Persistence: a subagent_usage row carries the same totals.
      final usageRow =
          persisted.singleWhere((e) => e['type'] == 'subagent_usage');
      expect(usageRow['input_tokens'], 5);
      expect(usageRow['output_tokens'], 5);
      expect(usageRow['turn_count'], 1);

      // Live callback fired once with a snapshot.
      expect(liveCallbacks, hasLength(1));
      expect(liveCallbacks.single.turnCount, 1);
    });

    test('parallel subagents accumulate into a single subagentStats', () async {
      await manager.spawnParallel(tasks: ['A', 'B', 'C']);
      expect(manager.subagentStats.turnCount, 3);
      expect(manager.subagentStats.inputTokens, 15);
      expect(manager.subagentStats.outputTokens, 15);
    });

    test('coalesces streaming text deltas into a single assistant_message row',
        () async {
      // Without buffering, every TextDelta would be persisted as its own
      // `subagent_event` row, bloating the session log and the rendered
      // share transcript by ~28× on real sessions. The fix coalesces a
      // run of deltas into one row whose text is the concatenation.
      final coalescingManager = AgentManager(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _MultiDeltaFactory(),
        config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
        systemPrompt: 'You are a test agent.',
      );
      final persisted = <Map<String, dynamic>>[];
      coalescingManager.onPersistEvent =
          (type, data) => persisted.add({'type': type, ...data});

      await coalescingManager.spawnSubagent(task: 'streaming test');

      final assistantRows = persisted
          .where((e) =>
              e['type'] == 'subagent_event' &&
              (e['inner'] as Map)['type'] == 'assistant_message')
          .toList();

      expect(assistantRows, hasLength(1),
          reason:
              'three TextDelta chunks should coalesce into one persisted row');
      expect((assistantRows.single['inner'] as Map)['text'],
          'Hello streaming world.');
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

class _MultiDeltaFactory implements LlmClientFactory {
  @override
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) =>
      _MultiDeltaLlm();

  @override
  LlmClient createFromConfig({required String systemPrompt}) =>
      _MultiDeltaLlm();
}

class _MultiDeltaLlm implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield TextDelta('Hello ');
    yield TextDelta('streaming ');
    yield TextDelta('world.');
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}
