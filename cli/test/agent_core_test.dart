import 'dart:async';

import 'package:glue/glue.dart';
import 'package:glue/src/agent/agent_core.dart'
    show
        AgentEvent,
        AgentTextDelta,
        AgentToolCall,
        AgentToolResult,
        AgentDone,
        Role;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock LLM client
// ---------------------------------------------------------------------------

class MockLlmClient extends LlmClient {
  /// Queue of responses. Each call to [stream] pops the first entry.
  final List<List<LlmChunk>> responses = [];

  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockLlmClient mockLlm;
  late AgentCore agent;

  setUp(() {
    mockLlm = MockLlmClient();
    final mockTool = MockTool();
    agent = AgentCore(
      llm: mockLlm,
      tools: {mockTool.name: mockTool},
    );
  });

  test('simple text response emits AgentTextDelta events', () async {
    mockLlm.responses.add([
      TextDelta('Hello'),
      TextDelta(' world'),
    ]);

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

  test('UsageInfo increments tokenCount', () async {
    mockLlm.responses.add([
      TextDelta('ok'),
      UsageInfo(inputTokens: 10, outputTokens: 5),
    ]);

    await agent.run('count').toList();

    expect(agent.tokenCount, 15);
  });

  test('multiple UsageInfo chunks accumulate', () async {
    mockLlm.responses.add([
      UsageInfo(inputTokens: 3, outputTokens: 2),
    ]);

    await agent.run('a').toList();

    mockLlm.responses.add([
      UsageInfo(inputTokens: 7, outputTokens: 8),
    ]);

    await agent.run('b').toList();

    expect(agent.tokenCount, 20);
  });

  test('tool call flow: ToolCallComplete → completeToolCall → re-calls LLM',
      () async {
    final toolCall = ToolCall(
      id: 'call_1',
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
        unawaited(Future(() async {
          final result = await agent.executeTool(event.call);
          agent.completeToolCall(result);
        }));
      }
    }

    expect(events[0], isA<AgentToolCall>());
    expect((events[0] as AgentToolCall).call.id, 'call_1');
    expect(events[1], isA<AgentToolResult>());
    expect((events[1] as AgentToolResult).result.content, 'mock result');
    expect((events[1] as AgentToolResult).result.success, isTrue);
    expect(events[2], isA<AgentTextDelta>());
    expect((events[2] as AgentTextDelta).delta, 'Done');
  });

  test('executeTool with known tool returns successful result', () async {
    final call = ToolCall(id: 'c1', name: 'test_tool', arguments: {});

    final result = await agent.executeTool(call);

    expect(result.callId, 'c1');
    expect(result.content, 'mock result');
    expect(result.success, isTrue);
  });

  test('executeTool with unknown tool returns error result', () async {
    final call = ToolCall(id: 'c2', name: 'no_such_tool', arguments: {});

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

    final call = ToolCall(id: 'c3', name: 'throwing_tool', arguments: {});
    final result = await agentWithThrowing.executeTool(call);

    expect(result.callId, 'c3');
    expect(result.content, contains('Tool error'));
    expect(result.content, contains('boom'));
    expect(result.success, isFalse);
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
      id: 'call_denied',
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
        unawaited(Future(() {
          agent.completeToolCall(ToolResult.denied(event.call.id));
        }));
      }
    }

    expect(events[0], isA<AgentToolCall>());
    expect(events[1], isA<AgentToolResult>());
    expect((events[1] as AgentToolResult).result.success, isFalse);
    expect(
      (events[1] as AgentToolResult).result.content,
      contains('denied'),
    );
    // LLM was called again and produced text
    expect(events[2], isA<AgentTextDelta>());
    expect((events[2] as AgentTextDelta).delta, 'Understood');
  });

  test('emits all tool calls before awaiting results (parallel)', () async {
    final toolCall1 = ToolCall(
      id: 'tc1',
      name: 'test_tool',
      arguments: {'path': 'a.txt'},
    );
    final toolCall2 = ToolCall(
      id: 'tc2',
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
        unawaited(Future(() async {
          final result = await agent.executeTool(event.call);
          agent.completeToolCall(result);
        }));
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
}
