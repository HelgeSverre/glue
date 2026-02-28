import 'package:glue/src/observability/debug_controller.dart';

class ObservabilitySpan {
  final String name;
  final String kind;
  final Map<String, dynamic> attributes;
  final DateTime _start;
  DateTime? _end;

  ObservabilitySpan({
    required this.name,
    required this.kind,
    Map<String, dynamic>? attributes,
  })  : attributes = attributes ?? {},
        _start = DateTime.now();

  Duration get duration => (_end ?? DateTime.now()).difference(_start);

  void end({Map<String, dynamic>? extra}) {
    _end = DateTime.now();
    if (extra != null) attributes.addAll(extra);
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'kind': kind,
        'start': _start.toIso8601String(),
        'end': _end?.toIso8601String(),
        'duration_ms': duration.inMilliseconds,
        'attributes': attributes,
      };
}

abstract class ObservabilitySink {
  void onSpan(ObservabilitySpan span);
  Future<void> flush();
  Future<void> close();
}

class Observability {
  final DebugController _debugController;
  final List<ObservabilitySink> _sinks = [];

  Observability({required DebugController debugController})
      : _debugController = debugController;

  bool get debugEnabled => _debugController.enabled;

  void addSink(ObservabilitySink sink) => _sinks.add(sink);

  ObservabilitySpan startSpan(String name, {String kind = 'internal', Map<String, dynamic>? attributes}) {
    return ObservabilitySpan(name: name, kind: kind, attributes: attributes);
  }

  void endSpan(ObservabilitySpan span, {Map<String, dynamic>? extra}) {
    span.end(extra: extra);
    for (final sink in _sinks) {
      sink.onSpan(span);
    }
  }

  Future<void> flush() async {
    for (final sink in _sinks) {
      await sink.flush();
    }
  }

  Future<void> close() async {
    for (final sink in _sinks) {
      await sink.close();
    }
  }
}
