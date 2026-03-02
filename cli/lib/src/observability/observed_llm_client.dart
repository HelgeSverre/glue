import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';

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
    bool hadError = false;
    final stopwatch = Stopwatch()..start();
    int? ttfbMs;
    try {
      await for (final chunk in _inner.stream(messages, tools: tools)) {
        if (ttfbMs == null && chunk is TextDelta) {
          ttfbMs = stopwatch.elapsedMilliseconds;
          span.attributes['llm.ttfb_ms'] = ttfbMs;
        }
        if (chunk is UsageInfo) {
          span.attributes['gen_ai.usage.input_tokens'] = chunk.inputTokens;
          span.attributes['gen_ai.usage.output_tokens'] = chunk.outputTokens;
          span.attributes['gen_ai.usage.total_tokens'] = chunk.totalTokens;
          span.attributes['input_tokens'] = chunk.inputTokens;
          span.attributes['output_tokens'] = chunk.outputTokens;
        }
        yield chunk;
      }
    } catch (e) {
      hadError = true;
      _obs.endSpan(span, extra: {'error': e.toString()});
      rethrow;
    } finally {
      if (!hadError) {
        _obs.endSpan(span);
      }
    }
  }
}
