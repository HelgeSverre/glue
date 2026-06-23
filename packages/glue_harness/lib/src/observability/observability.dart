import 'dart:async';
import 'dart:math';

import 'package:glue_harness/src/observability/debug_controller.dart';
import 'package:meta/meta.dart';

final _random = Random.secure();

String _hexId(int bytes) => List.generate(
  bytes,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class ObservabilityEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, dynamic> attributes;

  ObservabilityEvent(
    this.name, {
    DateTime? timestamp,
    Map<String, dynamic>? attributes,
  }) : timestamp = timestamp ?? DateTime.now(),
       attributes = attributes ?? {};

  Map<String, dynamic> toMap() => {
    'name': name,
    'timestamp': timestamp.toIso8601String(),
    if (attributes.isNotEmpty) 'attributes': attributes,
  };
}

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
  final List<ObservabilityEvent> events = [];
  DateTime? _end;
  String statusCode = 'unset';
  String? statusMessage;
  bool _ended = false;

  ObservabilitySpan({
    required this.name,
    required this.kind,
    String? traceId,
    this.parentSpanId,
    Map<String, dynamic>? attributes,
  }) : traceId = traceId ?? _hexId(16),
       spanId = _hexId(8),
       attributes = attributes ?? {},
       _start = DateTime.now();

  DateTime get start => _start;
  DateTime? get endTime => _end;
  Duration get duration => (_end ?? DateTime.now()).difference(_start);

  void addEvent(String name, {Map<String, dynamic>? attributes}) {
    if (_ended) return;
    events.add(ObservabilityEvent(name, attributes: attributes));
  }

  void setStatus(String code, {String? message}) {
    if (_ended) return;
    statusCode = code;
    statusMessage = message;
  }

  void end({Map<String, dynamic>? extra}) {
    if (_ended) return;
    _ended = true;
    _end = DateTime.now();
    if (extra != null) {
      attributes.addAll(extra);
      if (extra['error'] == true) {
        statusCode = 'error';
        statusMessage =
            extra['error.message']?.toString() ?? extra['error']?.toString();
      }
    }
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
    'status_code': statusCode,
    if (statusMessage != null) 'status_message': statusMessage,
    if (events.isNotEmpty) 'events': events.map((e) => e.toMap()).toList(),
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

  Observability({required this._debugController});

  bool get debugEnabled => _debugController.enabled;

  @visibleForTesting
  int get sinkCount => _sinks.length;

  @visibleForTesting
  bool get autoFlushEnabled => _flushTimer != null;

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

  /// Runs [body] inside a span named [name], owning the start/end lifecycle.
  ///
  /// The span is started with [kind]/[attributes]/[parent] (the same shape as
  /// [startSpan]), passed to [body], and always ended — even when [body]
  /// throws. On success the span is closed with the attributes returned by
  /// [onSuccess] (if provided); on error it is closed with the standard
  /// `error.*` attributes followed by anything [onError] contributes, then the
  /// error is rethrown. This owns the start-span / end-span boilerplate so
  /// callers stop hand-rolling try/catch span management.
  Future<T> withSpan<T>(
    String name, {
    String kind = 'internal',
    Map<String, dynamic>? attributes,
    ObservabilitySpan? parent,
    required Future<T> Function(ObservabilitySpan span) body,
    Map<String, dynamic> Function(T value)? onSuccess,
    Map<String, dynamic> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final span = startSpan(
      name,
      kind: kind,
      attributes: attributes,
      parent: parent,
    );
    try {
      final value = await body(span);
      endSpan(span, extra: onSuccess?.call(value));
      return value;
    } catch (e, st) {
      endSpan(
        span,
        extra: {
          'error': true,
          'error.type': e.runtimeType.toString(),
          'error.message': e.toString(),
          'error.stack': st.toString(),
          ...?onError?.call(e, st),
        },
      );
      rethrow;
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
