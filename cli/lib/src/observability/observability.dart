import 'dart:math';

import 'package:glue/src/observability/debug_controller.dart';

final _random = Random.secure();

String _hexId(int bytes) =>
    List.generate(bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

class ObservabilitySpan {
  final String name;
  final String kind;
  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final Map<String, dynamic> attributes;
  final DateTime _start;
  DateTime? _end;
  bool _ended = false;

  ObservabilitySpan({
    required this.name,
    required this.kind,
    String? traceId,
    this.parentSpanId,
    Map<String, dynamic>? attributes,
  })  : traceId = traceId ?? _hexId(16),
        spanId = _hexId(8),
        attributes = attributes ?? {},
        _start = DateTime.now();

  DateTime get start => _start;
  DateTime? get endTime => _end;
  Duration get duration => (_end ?? DateTime.now()).difference(_start);

  void end({Map<String, dynamic>? extra}) {
    if (_ended) return;
    _ended = true;
    _end = DateTime.now();
    if (extra != null) attributes.addAll(extra);
  }

  Map<String, dynamic> toMap() => {
        'traceId': traceId,
        'spanId': spanId,
        if (parentSpanId != null) 'parentSpanId': parentSpanId,
        'name': name,
        'kind': kind,
        'start': _start.toIso8601String(),
        'endTime': _end?.toIso8601String(),
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

  ObservabilitySpan startSpan(
    String name, {
    String kind = 'internal',
    Map<String, dynamic>? attributes,
    ObservabilitySpan? parent,
  }) {
    return ObservabilitySpan(
      name: name,
      kind: kind,
      attributes: attributes,
      traceId: parent?.traceId,
      parentSpanId: parent?.spanId,
    );
  }

  void endSpan(ObservabilitySpan span, {Map<String, dynamic>? extra}) {
    span.end(extra: extra);
    for (final sink in _sinks) {
      sink.onSpan(span);
    }
  }

  Future<void> flush() async {
    await Future.wait(_sinks.map((s) => s.flush()));
  }

  Future<void> close() async {
    await Future.wait(_sinks.map((s) => s.close()));
  }
}
