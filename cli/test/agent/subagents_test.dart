import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/subagents.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/llm/llm_factory.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
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

class _RecordingSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _SpanRecordingLlm implements LlmClient {
  _SpanRecordingLlm({
    required this.obs,
    required this.expectedParents,
  });

  final Observability obs;
  final Map<String, String?> expectedParents;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final task = messages.lastWhere((m) => m.role == Role.user).text!;
    expectedParents[task] = obs.activeSpan?.spanId;

    // Task A records a child span while Task B's LLM stream is still active.
    // Without per-subagent Zone holders, that child can inherit Task B's span.
    final delay = task.endsWith('A')
        ? const Duration(milliseconds: 20)
        : const Duration(milliseconds: 80);
    await Future<void>.delayed(delay);

    final child = obs.startSpan('llm.child.$task', kind: 'llm.child');
    obs.endSpan(child);
    yield TextDelta('Processed: $task');
    yield UsageInfo(inputTokens: 5, outputTokens: 5);
  }
}

class _SpanRecordingFactory implements LlmClientFactory {
  _SpanRecordingFactory({
    required this.obs,
    required this.expectedParents,
  });

  final Observability obs;
  final Map<String, String?> expectedParents;

  @override
  LlmClient createFor(ModelRef ref, {required String systemPrompt}) =>
      _SpanRecordingLlm(obs: obs, expectedParents: expectedParents);

  @override
  LlmClient createFromConfig({required String systemPrompt}) =>
      _SpanRecordingLlm(obs: obs, expectedParents: expectedParents);
}

void main() {
  group('Subagents', () {
    late Subagents manager;

    setUp(() {
      manager = Subagents(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _EchoFactory(),
        config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
        systemPrompt: 'You are a test agent.',
      );
    });

    test('spawns a single subagent', () async {
      final result = await manager.spawn(task: 'Do something');
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

    test('parallel subagents keep independent observability contexts',
        () async {
      final obs = Observability(debugController: DebugController());
      final sink = _RecordingSink();
      obs.addSink(sink);
      final expectedParents = <String, String?>{};
      final manager = Subagents(
        tools: {'read_file': ReadFileTool()},
        llmFactory: _SpanRecordingFactory(
          obs: obs,
          expectedParents: expectedParents,
        ),
        config: testConfig(env: {'ANTHROPIC_API_KEY': 'sk-test'}),
        systemPrompt: 'You are a test agent.',
        obs: obs,
      );

      final root = obs.startSpan('agent.turn');
      await obs.runInSpan(root, () async {
        final results = await manager.spawnParallel(
          tasks: ['Task A', 'Task B'],
        );
        expect(results, hasLength(2));
        expect(obs.activeSpan, same(root));
      });

      for (final task in ['Task A', 'Task B']) {
        final child =
            sink.spans.singleWhere((span) => span.name == 'llm.child.$task');
        expect(child.parentSpanId, expectedParents[task]);
      }
    });

    test('enforces max depth', () async {
      expect(
        () => manager.spawn(task: 'deep', currentDepth: 3),
        throwsA(isA<Exception>()),
      );
    });
  });
}
