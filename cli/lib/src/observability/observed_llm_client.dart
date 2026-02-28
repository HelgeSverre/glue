import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';

class ObservedLlmClient implements LlmClient {
  final LlmClient _inner;
  final Observability _obs;

  ObservedLlmClient({required LlmClient inner, required Observability obs})
      : _inner = inner,
        _obs = obs;

  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
    final span = _obs.startSpan(
      'llm.stream',
      kind: 'llm',
      attributes: {'message_count': messages.length},
    );
    bool hadError = false;
    try {
      await for (final chunk in _inner.stream(messages, tools: tools)) {
        if (chunk is UsageInfo) {
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
