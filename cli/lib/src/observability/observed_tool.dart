import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';

String _truncate(String s, int maxLen) =>
    s.length <= maxLen ? s : s.substring(0, maxLen);

class ObservedTool extends ForwardingTool {
  final Observability _obs;

  ObservedTool({required Tool inner, required Observability obs})
      : _obs = obs,
        super(inner);

  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async {
    final span = _obs.startSpan(
      'tool.${inner.name}',
      kind: 'tool',
      attributes: {'tool.name': inner.name, 'tool.args': args},
    );
    try {
      final result = await inner.execute(args);
      final text = ContentPart.textOnly(result);
      _obs.endSpan(span, extra: {
        'tool.result_length': text.length,
        'tool.result_preview': _truncate(text, 500),
        'tool.success': true,
      });
      return result;
    } catch (e) {
      _obs.endSpan(span, extra: {
        'error': true,
        'exception.type': e.runtimeType.toString(),
        'exception.message': e.toString(),
        'tool.success': false,
      });
      rethrow;
    }
  }
}

Map<String, Tool> wrapToolsWithObservability(
  Map<String, Tool> tools,
  Observability obs,
) {
  return {
    for (final entry in tools.entries)
      entry.key: ObservedTool(inner: entry.value, obs: obs),
  };
}
