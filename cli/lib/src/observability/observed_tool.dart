import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/observability.dart';

class ObservedTool extends Tool {
  final Tool _inner;
  final Observability _obs;

  ObservedTool({required Tool inner, required Observability obs})
      : _inner = inner,
        _obs = obs;

  @override
  String get name => _inner.name;

  @override
  String get description => _inner.description;

  @override
  List<ToolParameter> get parameters => _inner.parameters;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final span = _obs.startSpan(
      'tool.${_inner.name}',
      kind: 'tool',
      attributes: {'tool.name': _inner.name, 'tool.args': args},
    );
    try {
      final result = await _inner.execute(args);
      _obs.endSpan(span, extra: {'tool.result_length': result.length});
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
