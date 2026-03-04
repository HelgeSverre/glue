import 'dart:async';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observed_llm_client.dart';
import 'package:test/test.dart';

class _MockSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _MockLlmClient extends LlmClient {
  final List<List<LlmChunk>> responses = [];
  bool throwOnStream = false;
  String errorMessage = 'stream error';

  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
    if (throwOnStream) throw Exception(errorMessage);
    if (responses.isEmpty) return;
    final chunks = responses.removeAt(0);
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

void main() {
  late _MockLlmClient mockLlm;
  late _MockSink sink;
  late Observability obs;
  late ObservedLlmClient client;

  setUp(() {
    mockLlm = _MockLlmClient();
    sink = _MockSink();
    obs = Observability(debugController: DebugController());
    obs.addSink(sink);
    client = ObservedLlmClient(
      inner: mockLlm,
      obs: obs,
      provider: 'anthropic',
      model: 'claude-sonnet-4-20250514',
    );
  });

  test('yields all chunks from inner stream', () async {
    mockLlm.responses.add([
      TextDelta('Hello'),
      TextDelta(' world'),
    ]);

    final chunks = await client.stream([Message.user('hi')]).toList();

    expect(chunks, hasLength(2));
    expect((chunks[0] as TextDelta).text, 'Hello');
    expect((chunks[1] as TextDelta).text, ' world');
  });

  test('creates and ends span on stream completion', () async {
    mockLlm.responses.add([TextDelta('ok')]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans, hasLength(1));
    expect(sink.spans.first.name, 'llm.stream');
    expect(sink.spans.first.kind, 'llm');
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('records message_count attribute', () async {
    mockLlm.responses.add([TextDelta('ok')]);
    final messages = [Message.user('a'), Message.user('b')];

    await client.stream(messages).toList();

    expect(sink.spans.first.attributes['message_count'], 2);
  });

  test('records input_tokens and output_tokens from UsageInfo', () async {
    mockLlm.responses.add([
      TextDelta('ok'),
      UsageInfo(inputTokens: 100, outputTokens: 50),
    ]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes['input_tokens'], 100);
    expect(sink.spans.first.attributes['output_tokens'], 50);
  });

  test('ends span with error on exception', () async {
    mockLlm.throwOnStream = true;

    expect(
      () => client.stream([Message.user('hi')]).toList(),
      throwsA(isA<Exception>()),
    );

    await Future<void>.delayed(Duration.zero);

    expect(sink.spans, hasLength(1));
    expect(sink.spans.first.attributes['error'], isTrue);
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('does not double-end span on error', () async {
    mockLlm.throwOnStream = true;

    try {
      await client.stream([Message.user('hi')]).toList();
    } catch (_) {}

    expect(sink.spans, hasLength(1));
  });

  test('ends span on stream cancellation', () async {
    mockLlm.responses.add([
      TextDelta('a'),
      TextDelta('b'),
      TextDelta('c'),
    ]);

    final sub = client.stream([Message.user('hi')]).listen(null);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(sink.spans, hasLength(1));
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('records gen_ai.system and gen_ai.request.model', () async {
    mockLlm.responses.add([TextDelta('ok')]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes['gen_ai.system'], 'anthropic');
    expect(sink.spans.first.attributes['gen_ai.request.model'],
        'claude-sonnet-4-20250514');
  });

  test('records gen_ai.usage attributes from UsageInfo', () async {
    mockLlm.responses.add([
      TextDelta('ok'),
      UsageInfo(inputTokens: 100, outputTokens: 50),
    ]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes['gen_ai.usage.input_tokens'], 100);
    expect(sink.spans.first.attributes['gen_ai.usage.output_tokens'], 50);
    expect(sink.spans.first.attributes['gen_ai.usage.total_tokens'], 150);
  });

  test('records llm.ttfb_ms on first TextDelta', () async {
    mockLlm.responses.add([
      TextDelta('hello'),
      TextDelta(' world'),
      UsageInfo(inputTokens: 100, outputTokens: 50),
    ]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes['llm.ttfb_ms'], isA<int>());
    expect(sink.spans.first.attributes['llm.ttfb_ms'], greaterThanOrEqualTo(0));
  });

  test('does not set llm.ttfb_ms when no TextDelta is emitted', () async {
    mockLlm.responses.add([
      UsageInfo(inputTokens: 100, outputTokens: 50),
    ]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes.containsKey('llm.ttfb_ms'), isFalse);
  });

  test('omits gen_ai attributes when provider and model are empty', () async {
    final plainClient = ObservedLlmClient(inner: mockLlm, obs: obs);
    mockLlm.responses.add([TextDelta('ok')]);

    await plainClient.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes.containsKey('gen_ai.system'), isFalse);
    expect(sink.spans.first.attributes.containsKey('gen_ai.request.model'),
        isFalse);
  });

  test('records llm.tool_calls list when LLM requests tools', () async {
    mockLlm.responses.add([
      ToolCallComplete(
          ToolCall(id: 'id1', name: 'bash', arguments: {'command': 'ls'})),
      ToolCallComplete(ToolCall(
          id: 'id2', name: 'read_file', arguments: {'path': 'x.dart'})),
    ]);

    await client.stream([Message.user('hi')]).toList();

    final toolCalls =
        sink.spans.first.attributes['llm.tool_calls'] as List<String>;
    expect(toolCalls, containsAll(['bash', 'read_file']));
  });

  test('records llm.stop_reason=tool_use when tool calls present', () async {
    mockLlm.responses.add([
      ToolCallComplete(
          ToolCall(id: 'id1', name: 'bash', arguments: {'command': 'pwd'})),
    ]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes['llm.stop_reason'], 'tool_use');
  });

  test('records llm.stop_reason=end_turn when no tool calls', () async {
    mockLlm.responses.add([TextDelta('done')]);

    await client.stream([Message.user('hi')]).toList();

    expect(sink.spans.first.attributes['llm.stop_reason'], 'end_turn');
  });

  test('records llm.response_preview truncated to 500 chars', () async {
    mockLlm.responses.add([TextDelta('y' * 1000)]);

    await client.stream([Message.user('hi')]).toList();

    final preview =
        sink.spans.first.attributes['llm.response_preview'] as String;
    expect(preview.length, 500);
  });

  test('records full response_preview when short', () async {
    mockLlm.responses.add([TextDelta('hello there')]);

    await client.stream([Message.user('hi')]).toList();

    expect(
      sink.spans.first.attributes['llm.response_preview'],
      'hello there',
    );
  });

  test('records exception.type and exception.message on error', () async {
    mockLlm.throwOnStream = true;
    mockLlm.errorMessage = 'API rate limit exceeded';

    try {
      await client.stream([Message.user('hi')]).toList();
    } catch (_) {}

    final attrs = sink.spans.first.attributes;
    expect(attrs['exception.type'], contains('Exception'));
    expect(attrs['exception.message'], contains('API rate limit exceeded'));
    expect(attrs['error'], isTrue);
  });
}
