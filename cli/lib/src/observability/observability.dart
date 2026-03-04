import 'dart:async';
import 'dart:math';

import 'package:glue/src/observability/debug_controller.dart';

final _random = Random.secure();

String _hexId(int bytes) => List.generate(
        bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
    .join();

/// A span representing a unit of work in the observability trace.
///
/// {@category Observability}
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
        'trace_id': traceId,
        'span_id': spanId,
        if (parentSpanId != null) 'parent_span_id': parentSpanId,
        'name': name,
        'kind': kind,
        'start_time': _start.toIso8601String(),
        'end_time': _end?.toIso8601String(),
        'duration_ms': duration.inMilliseconds,
        'attributes': attributes,
      };
}

/// A sink that receives completed spans for export to an observability backend.
abstract class ObservabilitySink {
  /// Receives a completed [span] for processing.
  void onSpan(ObservabilitySpan span);

  /// Flushes any buffered spans to the backend.
  Future<void> flush();

  /// Closes this sink, releasing any held resources.
  Future<void> close();
}

/// Central coordinator for tracing spans and routing them to registered sinks.
class Observability {
  final DebugController _debugController;
  final List<ObservabilitySink> _sinks = [];
  Timer? _flushTimer;
  bool _isFlushing = false;

  // TODO: use Zone values for concurrent turn support instead of mutable field.
  ObservabilitySpan? activeSpan;

  Observability({required DebugController debugController})
      : _debugController = debugController;

  bool get debugEnabled => _debugController.enabled;

  /// Registers a [sink] to receive completed spans.
  void addSink(ObservabilitySink sink) => _sinks.add(sink);

  /// Starts a new span with the given [name].
  ObservabilitySpan startSpan(
    String name, {
    String kind = 'internal',
    Map<String, dynamic>? attributes,
    ObservabilitySpan? parent,
  }) {
    final effectiveParent = parent ?? activeSpan;
    return ObservabilitySpan(
      name: name,
      kind: kind,
      attributes: attributes,
      traceId: effectiveParent?.traceId,
      parentSpanId: effectiveParent?.spanId,
    );
  }

  /// Ends a [span] and forwards it to all registered sinks.
  void endSpan(ObservabilitySpan span, {Map<String, dynamic>? extra}) {
    span.end(extra: extra);
    for (final sink in _sinks) {
      sink.onSpan(span);
    }
  }

  void startAutoFlush(Duration interval) {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(interval, (_) {
      if (!_isFlushing) {
        _isFlushing = true;
        flush().whenComplete(() => _isFlushing = false);
      }
    });
  }

  /// Flushes all registered sinks.
  Future<void> flush() async {
    await Future.wait(_sinks.map((s) => s.flush()));
  }

  /// Closes all registered sinks.
  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await Future.wait(_sinks.map((s) => s.close()));
  }
}
