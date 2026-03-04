import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';

String _truncate(String s, int maxLen) =>
    s.length <= maxLen ? s : s.substring(0, maxLen);

class ObservedLlmClient implements LlmClient {
  final LlmClient _inner;
  final Observability _obs;
  final String _provider;
  final String _model;

  ObservedLlmClient({
    required LlmClient inner,
    required Observability obs,
    String provider = '',
    String model = '',
  })  : _inner = inner,
        _obs = obs,
        _provider = provider,
        _model = model;

  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
    final span = _obs.startSpan(
      'llm.stream',
      kind: 'llm',
      attributes: {
        'message_count': messages.length,
        if (_provider.isNotEmpty) 'gen_ai.system': _provider,
        if (_model.isNotEmpty) 'gen_ai.request.model': _model,
      },
    );
    final stopwatch = Stopwatch()..start();
    int? ttfbMs;
    final toolCallNames = <String>[];
    final responseBuffer = StringBuffer();
    var spanEnded = false;
    try {
      await for (final chunk in _inner.stream(messages, tools: tools)) {
        if (ttfbMs == null && chunk is TextDelta) {
          ttfbMs = stopwatch.elapsedMilliseconds;
          span.attributes['llm.ttfb_ms'] = ttfbMs;
        }
        switch (chunk) {
          case UsageInfo():
            span.attributes['gen_ai.usage.input_tokens'] = chunk.inputTokens;
            span.attributes['gen_ai.usage.output_tokens'] = chunk.outputTokens;
            span.attributes['gen_ai.usage.total_tokens'] = chunk.totalTokens;
            span.attributes['input_tokens'] = chunk.inputTokens;
            span.attributes['output_tokens'] = chunk.outputTokens;
          case ToolCallComplete(:final toolCall):
            toolCallNames.add(toolCall.name);
          case TextDelta(:final text):
            responseBuffer.write(text);
          default:
            break;
        }
        yield chunk;
      }
      final stopReason = toolCallNames.isNotEmpty ? 'tool_use' : 'end_turn';
      spanEnded = true;
      _obs.endSpan(span, extra: {
        'llm.stop_reason': stopReason,
        if (toolCallNames.isNotEmpty) 'llm.tool_calls': toolCallNames,
        if (responseBuffer.isNotEmpty)
          'llm.response_preview': _truncate(responseBuffer.toString(), 500),
      });
    } catch (e) {
      spanEnded = true;
      _obs.endSpan(span, extra: {
        'error': true,
        'exception.type': e.runtimeType.toString(),
        'exception.message': e.toString(),
      });
      rethrow;
    } finally {
      if (!spanEnded) _obs.endSpan(span);
    }
  }
}
