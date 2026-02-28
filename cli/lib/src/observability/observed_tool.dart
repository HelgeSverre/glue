import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';

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
      final textLength = ContentPart.textOnly(result).length;
      _obs.endSpan(span, extra: {'tool.result_length': textLength});
      return result;
    } catch (e) {
      _obs.endSpan(span, extra: {'error': e.toString()});
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
