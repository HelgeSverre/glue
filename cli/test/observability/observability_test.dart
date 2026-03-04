import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:test/test.dart';

class _MockSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];
  int flushCount = 0;
  int closeCount = 0;

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async => flushCount++;

  @override
  Future<void> close() async => closeCount++;
}

void main() {
  group('ObservabilitySpan', () {
    test('traceId is 32 hex characters', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      expect(span.traceId, hasLength(32));
      expect(span.traceId, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('spanId is 16 hex characters', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      expect(span.spanId, hasLength(16));
      expect(span.spanId, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('two spans get different IDs', () {
      final a = ObservabilitySpan(name: 'a', kind: 'internal');
      final b = ObservabilitySpan(name: 'b', kind: 'internal');
      expect(a.traceId, isNot(equals(b.traceId)));
      expect(a.spanId, isNot(equals(b.spanId)));
    });

    test('parent tracking inherits traceId and sets parentSpanId', () {
      final parent = ObservabilitySpan(name: 'parent', kind: 'internal');
      final child = ObservabilitySpan(
        name: 'child',
        kind: 'internal',
        traceId: parent.traceId,
        parentSpanId: parent.spanId,
      );
      expect(child.traceId, equals(parent.traceId));
      expect(child.parentSpanId, equals(parent.spanId));
      expect(child.spanId, isNot(equals(parent.spanId)));
    });

    test('span without parent has null parentSpanId', () {
      final span = ObservabilitySpan(name: 'root', kind: 'internal');
      expect(span.parentSpanId, isNull);
    });

    test('end() sets endTime', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      expect(span.endTime, isNull);
      span.end();
      expect(span.endTime, isNotNull);
    });

    test('end() is idempotent', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      final firstEnd = span.endTime;
      span.end();
      expect(span.endTime, equals(firstEnd));
    });

    test('end() with extra attributes merges them', () {
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'existing': 'value'},
      );
      span.end(extra: {'added': 42});
      expect(span.attributes['existing'], 'value');
      expect(span.attributes['added'], 42);
    });

    test('end() called twice does not merge extras from second call', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end(extra: {'first': 1});
      span.end(extra: {'second': 2});
      expect(span.attributes['first'], 1);
      expect(span.attributes.containsKey('second'), isFalse);
    });

    test('toMap() contains all expected keys', () {
      final span = ObservabilitySpan(
        name: 'test-span',
        kind: 'http',
        attributes: {'key': 'val'},
      );
      span.end();
      final map = span.toMap();
      expect(map['trace_id'], span.traceId);
      expect(map['span_id'], span.spanId);
      expect(map['name'], 'test-span');
      expect(map['kind'], 'http');
      expect(map['start_time'], isA<String>());
      expect(map['end_time'], isA<String>());
      expect(map['duration_ms'], isA<int>());
      expect(map['attributes'], isA<Map<String, dynamic>>());
    });

    test('toMap() includes parentSpanId when set', () {
      final span = ObservabilitySpan(
        name: 'child',
        kind: 'internal',
        parentSpanId: 'abc123',
      );
      expect(span.toMap().containsKey('parent_span_id'), isTrue);
      expect(span.toMap()['parent_span_id'], 'abc123');
    });

    test('toMap() omits parentSpanId when null', () {
      final span = ObservabilitySpan(name: 'root', kind: 'internal');
      expect(span.toMap().containsKey('parent_span_id'), isFalse);
    });

    test('duration is zero or positive before end', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      expect(span.duration.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('duration is fixed after end', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      final d1 = span.duration;
      final d2 = span.duration;
      expect(d1, equals(d2));
    });
  });

  group('Observability', () {
    late DebugController debugController;
    late Observability obs;

    setUp(() {
      debugController = DebugController();
      obs = Observability(debugController: debugController);
    });

    test('startSpan without parent generates fresh traceId', () {
      final span = obs.startSpan('test');
      expect(span.traceId, hasLength(32));
      expect(span.parentSpanId, isNull);
    });

    test('startSpan with parent inherits traceId and sets parentSpanId', () {
      final parent = obs.startSpan('parent');
      final child = obs.startSpan('child', parent: parent);
      expect(child.traceId, equals(parent.traceId));
      expect(child.parentSpanId, equals(parent.spanId));
    });

    test('endSpan dispatches to all registered sinks', () {
      final sink1 = _MockSink();
      final sink2 = _MockSink();
      obs.addSink(sink1);
      obs.addSink(sink2);

      final span = obs.startSpan('test');
      obs.endSpan(span);

      expect(sink1.spans, hasLength(1));
      expect(sink2.spans, hasLength(1));
      expect(sink1.spans.first.name, 'test');
    });

    test('endSpan passes extra attributes', () {
      final sink = _MockSink();
      obs.addSink(sink);

      final span = obs.startSpan('test');
      obs.endSpan(span, extra: {'status': 200});

      expect(sink.spans.first.attributes['status'], 200);
    });

    test('flush calls flush on all sinks', () async {
      final sink1 = _MockSink();
      final sink2 = _MockSink();
      obs.addSink(sink1);
      obs.addSink(sink2);

      await obs.flush();

      expect(sink1.flushCount, 1);
      expect(sink2.flushCount, 1);
    });

    test('close calls close on all sinks', () async {
      final sink1 = _MockSink();
      final sink2 = _MockSink();
      obs.addSink(sink1);
      obs.addSink(sink2);

      await obs.close();

      expect(sink1.closeCount, 1);
      expect(sink2.closeCount, 1);
    });

    test('debugEnabled delegates to DebugController', () {
      expect(obs.debugEnabled, isFalse);
      debugController.enable();
      expect(obs.debugEnabled, isTrue);
      debugController.disable();
      expect(obs.debugEnabled, isFalse);
    });

    test('startAutoFlush creates periodic flush and close cancels it',
        () async {
      final sink = _MockSink();
      obs.addSink(sink);
      obs.startAutoFlush(const Duration(milliseconds: 10));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      final countBeforeClose = sink.flushCount;
      expect(countBeforeClose, greaterThanOrEqualTo(1));

      await obs.close();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sink.flushCount, countBeforeClose);
    });

    test('activeSpan is used as default parent', () {
      final parent = obs.startSpan('parent');
      obs.activeSpan = parent;
      final child = obs.startSpan('child');
      expect(child.traceId, equals(parent.traceId));
      expect(child.parentSpanId, equals(parent.spanId));
      obs.activeSpan = null;
    });

    test('explicit parent overrides activeSpan', () {
      final active = obs.startSpan('active');
      obs.activeSpan = active;
      final explicit = obs.startSpan('explicit-parent');
      final child = obs.startSpan('child', parent: explicit);
      expect(child.traceId, equals(explicit.traceId));
      expect(child.parentSpanId, equals(explicit.spanId));
      obs.activeSpan = null;
    });

    test('startSpan without activeSpan generates fresh traceId', () {
      obs.activeSpan = null;
      final span = obs.startSpan('test');
      expect(span.parentSpanId, isNull);
    });
  });
}
