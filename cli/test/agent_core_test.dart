import 'dart:async';

import 'package:glue_core/glue_core.dart';
import 'package:glue/glue.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock LLM client
// ---------------------------------------------------------------------------

class MockLlmClient extends LlmClient {
  /// Queue of responses. Each call to [stream] pops the first entry.
  final List<List<LlmChunk>> responses = [];

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    if (responses.isEmpty) return;
    final chunks = responses.removeAt(0);
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

// ---------------------------------------------------------------------------
// Mock tool
// ---------------------------------------------------------------------------

class MockTool extends Tool {
  @override
  String get name => 'test_tool';

  @override
  String get description => 'A test tool';

  @override
  List<ToolParameter> get parameters => [];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult(content: 'mock result');
}

class ThrowingTool extends Tool {
  @override
  String get name => 'throwing_tool';

  @override
  String get description => 'A tool that throws';

  @override
  List<ToolParameter> get parameters => [];

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      throw Exception('boom');
}

/// Collects every completed span so tests can assert on `executeTool`'s
/// observability output (routed through `Observability.withSpan`).
class _CollectingSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockLlmClient mockLlm;
  late AgentCore agent;

  setUp(() {
    mockLlm = MockLlmClient();
    final mockTool = MockTool();
    agent = AgentCore(llm: mockLlm, tools: {mockTool.name: mockTool});
  });

  test('simple text response emits AgentTextDelta events', () async {
    mockLlm.responses.add([TextDelta('Hello'), TextDelta(' world')]);

    final events = await agent.run('Hi').toList();

    expect(events, hasLength(3));
    expect(events[0], isA<AgentTextDelta>());
    expect((events[0] as AgentTextDelta).delta, 'Hello');
    expect(events[1], isA<AgentTextDelta>());
    expect((events[1] as AgentTextDelta).delta, ' world');
    expect(events[2], isA<AgentDone>());
  });

  test('conversation updated after text response', () async {
    mockLlm.responses.add([TextDelta('Hi there')]);

    await agent.run('Hello').toList();

    expect(agent.conversation, hasLength(2));
    expect(agent.conversation[0].text, 'Hello');
    expect(agent.conversation[1].text, 'Hi there');
  });

  test('forwards ThinkingDelta as AgentThinkingDelta and never appends '
      'thinking to assistantText', () async {
    mockLlm.responses.add([
      ThinkingDelta('reasoning step '),
      ThinkingDelta('two'),
      TextDelta('the answer'),
    ]);

    final events = await agent.run('hi').toList();
    expect(
      events.whereType<AgentThinkingDelta>().map((e) => e.delta).toList(),
      ['reasoning step ', 'two'],
    );
    expect(events.whereType<AgentTextDelta>().map((e) => e.delta).toList(), [
      'the answer',
    ]);
    // Thinking content must NOT leak into the assistant message that
    // gets sent back to the model on the next turn.
    final assistant = agent.conversation.last;
    expect(assistant.text, 'the answer');
  });

  test('UsageInfo updates stats.totalTokens', () async {
    mockLlm.responses.add([
      TextDelta('ok'),
      UsageInfo(inputTokens: 10, outputTokens: 5),
    ]);

    await agent.run('count').toList();

    expect(agent.stats.totalTokens, 15);
  });

  test(
    'multiple UsageInfo chunks accumulate including cache buckets',
    () async {
      mockLlm.responses.add([
        UsageInfo(inputTokens: 3, outputTokens: 2, cacheReadTokens: 100),
      ]);

      await agent.run('a').toList();

      mockLlm.responses.add([
        UsageInfo(inputTokens: 7, outputTokens: 8, cacheCreationTokens: 50),
      ]);

      await agent.run('b').toList();

      // 3 + 2 + 100 + 7 + 8 + 50
      expect(agent.stats.totalTokens, 170);
      // Sanity: input + output only is 20, distinct from totalTokens.
      expect(agent.stats.inputTokens + agent.stats.outputTokens, 20);
    },
  );

  test(
    'lastTurnInputTokens reflects billed input of the latest turn only',
    () async {
      // First turn: billed input = 1200 + 300 = 1500.
      mockLlm.responses.add([
        TextDelta('a'),
        UsageInfo(inputTokens: 1200, outputTokens: 40, cacheReadTokens: 300),
      ]);
      await agent.run('first').toList();
      expect(agent.lastTurnInputTokens, 1500);

      // Second turn overwrites (not cumulative): 2000 + 0 = 2000.
      mockLlm.responses.add([
        TextDelta('b'),
        UsageInfo(inputTokens: 2000, outputTokens: 10),
      ]);
      await agent.run('second').toList();
      expect(agent.lastTurnInputTokens, 2000);
    },
  );

  test(
    'tool call flow: ToolCallComplete → completeToolCall → re-calls LLM',
    () async {
      final toolCall = ToolCall(
        id: const ToolCallId('call_1'),
        name: 'test_tool',
        arguments: {},
      );

      // First LLM call: returns a tool call
      mockLlm.responses.add([ToolCallComplete(toolCall)]);
      // Second LLM call (after tool result): returns text
      mockLlm.responses.add([TextDelta('Done')]);

      final events = <AgentEvent>[];
      final stream = agent.run('do something');

      await for (final event in stream) {
        events.add(event);
        if (event is AgentToolCall) {
          // Schedule completion asynchronously so the agent loop can set up
          // its completer before we complete it.
          unawaited(
            Future(() async {
              final result = await agent.executeTool(event.call);
              agent.completeToolCall(result);
            }),
          );
        }
      }

      expect(events[0], isA<AgentToolCall>());
      expect((events[0] as AgentToolCall).call.id, 'call_1');
      expect(events[1], isA<AgentToolResult>());
      expect((events[1] as AgentToolResult).result.content, 'mock result');
      expect((events[1] as AgentToolResult).result.success, isTrue);
      expect(events[2], isA<AgentTextDelta>());
      expect((events[2] as AgentTextDelta).delta, 'Done');
    },
  );

  test('executeTool with known tool returns successful result', () async {
    final call = ToolCall(
      id: const ToolCallId('c1'),
      name: 'test_tool',
      arguments: {},
    );

    final result = await agent.executeTool(call);

    expect(result.callId, 'c1');
    expect(result.content, 'mock result');
    expect(result.success, isTrue);
  });

  test('executeTool with unknown tool returns error result', () async {
    final call = ToolCall(
      id: const ToolCallId('c2'),
      name: 'no_such_tool',
      arguments: {},
    );

    final result = await agent.executeTool(call);

    expect(result.callId, 'c2');
    expect(result.content, contains('Unknown tool'));
    expect(result.success, isFalse);
  });

  test('executeTool with throwing tool returns error result', () async {
    final throwingTool = ThrowingTool();
    final agentWithThrowing = AgentCore(
      llm: mockLlm,
      tools: {throwingTool.name: throwingTool},
    );

    final call = ToolCall(
      id: const ToolCallId('c3'),
      name: 'throwing_tool',
      arguments: {},
    );
    final result = await agentWithThrowing.executeTool(call);

    expect(result.callId, 'c3');
    expect(result.content, contains('Tool error'));
    expect(result.content, contains('boom'));
    expect(result.success, isFalse);
  });

  test('executeTool emits a successful tool span via withSpan', () async {
    final sink = _CollectingSink();
    final obs = Observability(debugController: DebugController())
      ..addSink(sink);
    final tool = MockTool();
    final agentWithObs = AgentCore(
      llm: mockLlm,
      tools: {tool.name: tool},
      obs: obs,
    );

    final call = ToolCall(
      id: const ToolCallId('s1'),
      name: 'test_tool',
      arguments: {'a': 1},
    );
    final result = await agentWithObs.executeTool(call);

    // Returned result is unchanged by the span wrapping.
    expect(result.callId, 's1');
    expect(result.success, isTrue);

    expect(sink.spans, hasLength(1));
    final span = sink.spans.single;
    expect(span.name, 'tool.test_tool');
    expect(span.attributes['tool.success'], isTrue);
    expect(span.attributes['tool.name'], 'test_tool');
    expect(span.attributes.containsKey('tool.duration_ms'), isTrue);
  });

  test('executeTool emits a failed tool span via withSpan', () async {
    final sink = _CollectingSink();
    final obs = Observability(debugController: DebugController())
      ..addSink(sink);
    final tool = ThrowingTool();
    final agentWithObs = AgentCore(
      llm: mockLlm,
      tools: {tool.name: tool},
      obs: obs,
    );

    final call = ToolCall(
      id: const ToolCallId('s2'),
      name: 'throwing_tool',
      arguments: {},
    );
    final result = await agentWithObs.executeTool(call);

    // Error path still returns a ToolResult (no rethrow) with empty metadata.
    expect(result.success, isFalse);
    expect(result.content, contains('Tool error'));
    expect(result.metadata, isEmpty);

    expect(sink.spans, hasLength(1));
    final span = sink.spans.single;
    expect(span.name, 'tool.throwing_tool');
    expect(span.attributes['tool.success'], isFalse);
    expect(span.attributes['error'], isTrue);
    expect(span.statusCode, 'error');
  });

  test('conversation history contains user + assistant messages', () async {
    mockLlm.responses.add([TextDelta('response')]);

    await agent.run('question').toList();

    expect(agent.conversation, hasLength(2));
    expect(agent.conversation[0].role, Role.user);
    expect(agent.conversation[0].text, 'question');
    expect(agent.conversation[1].role, Role.assistant);
    expect(agent.conversation[1].text, 'response');
  });

  test('multiple turns accumulate conversation history', () async {
    mockLlm.responses.add([TextDelta('first reply')]);
    await agent.run('first question').toList();

    mockLlm.responses.add([TextDelta('second reply')]);
    await agent.run('second question').toList();

    expect(agent.conversation, hasLength(4));
    expect(agent.conversation[0].text, 'first question');
    expect(agent.conversation[1].text, 'first reply');
    expect(agent.conversation[2].text, 'second question');
    expect(agent.conversation[3].text, 'second reply');
  });

  test('tool result denied still feeds back to LLM', () async {
    final toolCall = ToolCall(
      id: const ToolCallId('call_denied'),
      name: 'test_tool',
      arguments: {},
    );

    // First call: tool call
    mockLlm.responses.add([ToolCallComplete(toolCall)]);
    // Second call: text after denied result
    mockLlm.responses.add([TextDelta('Understood')]);

    final events = <AgentEvent>[];
    final stream = agent.run('do it');

    await for (final event in stream) {
      events.add(event);
      if (event is AgentToolCall) {
        unawaited(
          Future(() {
            agent.completeToolCall(ToolResult.denied(event.call.id));
          }),
        );
      }
    }

    expect(events[0], isA<AgentToolCall>());
    expect(events[1], isA<AgentToolResult>());
    expect((events[1] as AgentToolResult).result.success, isFalse);
    expect((events[1] as AgentToolResult).result.content, contains('denied'));
    // LLM was called again and produced text
    expect(events[2], isA<AgentTextDelta>());
    expect((events[2] as AgentTextDelta).delta, 'Understood');
  });

  test('emits all tool calls before awaiting results (parallel)', () async {
    final toolCall1 = ToolCall(
      id: const ToolCallId('tc1'),
      name: 'test_tool',
      arguments: {'path': 'a.txt'},
    );
    final toolCall2 = ToolCall(
      id: const ToolCallId('tc2'),
      name: 'test_tool',
      arguments: {'path': 'b.txt'},
    );

    // First LLM call: returns 2 tool calls
    mockLlm.responses.add([
      TextDelta('thinking'),
      ToolCallComplete(toolCall1),
      ToolCallComplete(toolCall2),
    ]);
    // Second LLM call: text response after results
    mockLlm.responses.add([TextDelta('done')]);

    final events = <AgentEvent>[];

    await for (final event in agent.run('test')) {
      events.add(event);
      if (event is AgentToolCall) {
        unawaited(
          Future(() async {
            final result = await agent.executeTool(event.call);
            agent.completeToolCall(result);
          }),
        );
      }
    }

    // Both AgentToolCall events should appear before any AgentToolResult
    final toolCallIndices = <int>[];
    final toolResultIndices = <int>[];
    for (var i = 0; i < events.length; i++) {
      if (events[i] is AgentToolCall) toolCallIndices.add(i);
      if (events[i] is AgentToolResult) toolResultIndices.add(i);
    }
    expect(toolCallIndices.length, 2);
    expect(toolResultIndices.length, 2);
    // All tool calls emitted before first result
    expect(toolCallIndices.last, lessThan(toolResultIndices.first));
  });

  // ── Soft fallback: ToolsNotSupportedException ─────────────────────────

  test('ToolsNotSupportedException on first call yields AgentNotice, '
      'disables tools, and retries the turn in chat-only mode', () async {
    // First call throws — second call must succeed without tools.
    final llm = _SoftFallbackLlm(
      'qwen2.5:7b',
      retryChunks: [
        TextDelta('Hello without tools.'),
        UsageInfo(inputTokens: 1, outputTokens: 1),
      ],
    );
    final softAgent = AgentCore(llm: llm, tools: {'test_tool': MockTool()});

    final events = await softAgent.run('hi').toList();

    // Exactly one AgentNotice fired, before AgentDone.
    final notices = events.whereType<AgentNotice>().toList();
    expect(notices, hasLength(1));
    expect(notices.first.kind, 'warning');
    expect(notices.first.message, contains('qwen2.5:7b'));
    expect(notices.first.message, contains('does not support tool calling'));

    // The retry produced normal text + AgentDone.
    final text = events.whereType<AgentTextDelta>().map((e) => e.delta).join();
    expect(text, 'Hello without tools.');
    expect(events.last, isA<AgentDone>());

    // No AgentError surfaced — soft fallback, not a crash.
    expect(events.whereType<AgentError>(), isEmpty);

    // Tools are now disabled for the rest of the session.
    expect(softAgent.toolFilter, isNotNull);
    expect(softAgent.allowedTools, isEmpty);

    // The second call received tools: null/empty — the retry was tool-less.
    expect(llm.lastCallToolsCount, 0);
  });
}

/// Mock LLM that throws ToolsNotSupportedException on the first call
/// and emits [retryChunks] on the second.
class _SoftFallbackLlm extends LlmClient {
  _SoftFallbackLlm(this.modelId, {required this.retryChunks});

  final String modelId;
  final List<LlmChunk> retryChunks;
  int _callCount = 0;
  int lastCallToolsCount = -1;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    _callCount++;
    lastCallToolsCount = tools?.length ?? 0;
    if (_callCount == 1) {
      throw ToolsNotSupportedException(modelId);
    }
    for (final chunk in retryChunks) {
      yield chunk;
    }
  }
}
