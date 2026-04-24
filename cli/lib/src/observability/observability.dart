import 'dart:async';
import 'dart:math';

import 'package:glue/src/observability/debug_controller.dart';
import 'package:meta/meta.dart';

final _random = Random.secure();

String _hexId(int bytes) => List.generate(
        bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
    .join();

class ObservabilityEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, dynamic> attributes;

  ObservabilityEvent(
    this.name, {
    DateTime? timestamp,
    Map<String, dynamic>? attributes,
  })  : timestamp = timestamp ?? DateTime.now(),
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
  })  : traceId = traceId ?? _hexId(16),
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
    // Default a closed span without an explicit status to `ok`. OTLP
    // backends (MLflow, Langfuse) treat `unset` as "still in progress",
    // which makes finished spans look like they're hanging in the UI.
    if (statusCode == 'unset') {
      statusCode = 'ok';
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

/// A mutable holder for the current [ObservabilitySpan], installed in a
/// [Zone] by [Observability.runInContext] so that concurrent agent turns
/// can each keep their own active span across `await` boundaries without
/// stepping on each other's state.
class _SpanHolder {
  ObservabilitySpan? span;
}

/// Central coordinator for tracing spans and routing them to registered sinks.
class Observability {
  static const _holderZoneKey = #glue.observability.span_holder;

  final DebugController _debugController;
  final List<ObservabilitySink> _sinks = [];
  Timer? _flushTimer;
  bool _isFlushing = false;

  /// Holder used when no zone-local context has been installed. Legacy
  /// callers that write directly to [activeSpan] without entering
  /// [runInContext] land here. When a zone context exists, it shadows this.
  final _SpanHolder _globalHolder = _SpanHolder();

  Observability({required DebugController debugController})
      : _debugController = debugController;

  _SpanHolder get _currentHolder =>
      (Zone.current[_holderZoneKey] as _SpanHolder?) ?? _globalHolder;

  /// The span that should act as parent for any new span started right now.
  ///
  /// Reads the zone-local holder installed by [runInContext] if one exists,
  /// otherwise the global fallback. Setting this updates the current
  /// holder, so the classic save/restore pattern inside [runInContext]
  /// mutates per-turn state instead of a shared field.
  ObservabilitySpan? get activeSpan => _currentHolder.span;
  set activeSpan(ObservabilitySpan? span) => _currentHolder.span = span;

  /// Runs [fn] inside a fresh observability context. Any mutations to
  /// [activeSpan] inside [fn] (including across `await` boundaries and
  /// transitive calls) stay scoped to this context, so concurrent turns or
  /// subagents spawned in sibling contexts don't overwrite each other's
  /// active span. No uncaught-error handler is installed — exceptions
  /// thrown inside [fn] propagate to the caller.
  R runInContext<R>(R Function() fn) =>
      runZoned(fn, zoneValues: {_holderZoneKey: _SpanHolder()});

  /// Convenience: [runInContext] that installs [span] as the initial
  /// [activeSpan] for the new context. Equivalent to
  /// `runInContext(() { activeSpan = span; return fn(); })`.
  R runInSpan<R>(ObservabilitySpan span, R Function() fn) => runInContext(() {
        activeSpan = span;
        return fn();
      });

  bool get debugEnabled => _debugController.enabled;

  @visibleForTesting
  int get sinkCount => _sinks.length;

  @visibleForTesting
  bool get autoFlushEnabled => _flushTimer != null;

  /// Registers a [sink] to receive completed spans.
  void addSink(ObservabilitySink sink) => _sinks.add(sink);

  /// Starts a new span with the given [name].
  ///
  /// `session.id` is inherited from the effective parent's attributes when
  /// the caller doesn't supply one — backends like Langfuse / OpenInference
  /// group spans by `session.id`, so every descendant of a session-tagged
  /// span needs to carry it explicitly rather than relying on traceId alone.
  ObservabilitySpan startSpan(
    String name, {
    String kind = 'internal',
    Map<String, dynamic>? attributes,
    ObservabilitySpan? parent,
  }) {
    final effectiveParent = parent ?? activeSpan;
    final merged = <String, dynamic>{...?attributes};
    final inheritedSessionId = effectiveParent?.attributes['session.id'];
    if (inheritedSessionId is String && inheritedSessionId.isNotEmpty) {
      merged.putIfAbsent('session.id', () => inheritedSessionId);
    }
    return ObservabilitySpan(
      name: name,
      kind: kind,
      attributes: merged,
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
