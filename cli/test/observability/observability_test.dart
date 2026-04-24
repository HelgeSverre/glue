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

    test('end() defaults statusCode to ok when no explicit status set', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      expect(span.statusCode, 'unset');
      span.end();
      expect(span.statusCode, 'ok');
    });

    test('end() preserves explicit status set before close', () {
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.setStatus('error', message: 'cancelled by user');
      span.end(extra: {'cancelled': true});
      expect(span.statusCode, 'error');
      expect(span.statusMessage, 'cancelled by user');
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

    test('startSpan inherits session.id from effective parent', () {
      final parent = obs.startSpan(
        'turn',
        attributes: {'session.id': 'sess-abc'},
      );
      final child = obs.startSpan('child', parent: parent);
      expect(child.attributes['session.id'], 'sess-abc');
    });

    test('startSpan inherits session.id from activeSpan when no parent given',
        () {
      final parent = obs.startSpan(
        'turn',
        attributes: {'session.id': 'sess-xyz'},
      );
      obs.activeSpan = parent;
      final child = obs.startSpan('child');
      expect(child.attributes['session.id'], 'sess-xyz');
      obs.activeSpan = null;
    });

    test('caller-supplied session.id wins over inherited value', () {
      final parent = obs.startSpan(
        'turn',
        attributes: {'session.id': 'parent-sess'},
      );
      final child = obs.startSpan(
        'child',
        parent: parent,
        attributes: {'session.id': 'child-sess'},
      );
      expect(child.attributes['session.id'], 'child-sess');
    });

    test('empty session.id on parent is not inherited', () {
      final parent = obs.startSpan(
        'turn',
        attributes: {'session.id': ''},
      );
      final child = obs.startSpan('child', parent: parent);
      expect(child.attributes.containsKey('session.id'), isFalse);
    });
  });

  group('Observability.runInContext', () {
    late Observability obs;

    setUp(() {
      obs = Observability(debugController: DebugController());
    });

    test('runInSpan installs the span as activeSpan inside the context', () {
      final span = obs.startSpan('turn');
      ObservabilitySpan? seen;
      obs.runInSpan(span, () {
        seen = obs.activeSpan;
      });
      expect(seen, same(span));
      expect(obs.activeSpan, isNull);
    });

    test('activeSpan propagates across await boundaries', () async {
      final span = obs.startSpan('turn');
      ObservabilitySpan? seenAfterAwait;
      await obs.runInSpan(span, () async {
        await Future<void>.delayed(Duration.zero);
        seenAfterAwait = obs.activeSpan;
      });
      expect(seenAfterAwait, same(span));
    });

    test('nested runInSpan restores the outer span on exit', () {
      final outer = obs.startSpan('outer');
      final inner = obs.startSpan('inner');
      ObservabilitySpan? innerSeen;
      ObservabilitySpan? afterInner;
      obs.runInSpan(outer, () {
        obs.runInSpan(inner, () {
          innerSeen = obs.activeSpan;
        });
        afterInner = obs.activeSpan;
      });
      expect(innerSeen, same(inner));
      expect(afterInner, same(outer));
    });

    test('concurrent contexts each keep their own activeSpan', () async {
      final spanA = obs.startSpan('a');
      final spanB = obs.startSpan('b');
      ObservabilitySpan? seenA;
      ObservabilitySpan? seenB;

      final futureA = obs.runInSpan(spanA, () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        seenA = obs.activeSpan;
      });
      final futureB = obs.runInSpan(spanB, () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        seenB = obs.activeSpan;
      });
      await Future.wait([futureA, futureB]);

      expect(seenA, same(spanA));
      expect(seenB, same(spanB));
    });

    test('save/restore pattern inside runInContext is per-context', () async {
      // Two concurrent "agent turns" each do the save/restore dance that
      // Agent uses during an LLM stream. Their mutations must not leak
      // into each other.
      final turnA = obs.startSpan('turnA');
      final turnB = obs.startSpan('turnB');
      final llmA = obs.startSpan('llmA');
      final llmB = obs.startSpan('llmB');

      ObservabilitySpan? midA;
      ObservabilitySpan? midB;
      ObservabilitySpan? endA;
      ObservabilitySpan? endB;

      Future<void> drive(
          ObservabilitySpan turn,
          ObservabilitySpan llm,
          void Function(ObservabilitySpan?) recordMid,
          void Function(ObservabilitySpan?) recordEnd) async {
        return obs.runInContext(() async {
          obs.activeSpan = turn;
          final saved = obs.activeSpan;
          obs.activeSpan = llm;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          recordMid(obs.activeSpan);
          obs.activeSpan = saved;
          recordEnd(obs.activeSpan);
        });
      }

      await Future.wait([
        drive(turnA, llmA, (s) => midA = s, (s) => endA = s),
        drive(turnB, llmB, (s) => midB = s, (s) => endB = s),
      ]);

      expect(midA, same(llmA));
      expect(midB, same(llmB));
      expect(endA, same(turnA));
      expect(endB, same(turnB));
    });

    test('exceptions thrown inside runInSpan propagate to the awaiter',
        () async {
      final span = obs.startSpan('boom');
      expect(
        () => obs.runInSpan<Future<void>>(span, () async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('synchronous exceptions propagate through runInSpan', () {
      final span = obs.startSpan('boom');
      expect(
        () => obs.runInSpan<void>(span, () {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('startSpan inside runInSpan picks up the context-local parent', () {
      final parent = obs.startSpan('parent');
      obs.runInSpan(parent, () {
        final child = obs.startSpan('child');
        expect(child.traceId, equals(parent.traceId));
        expect(child.parentSpanId, equals(parent.spanId));
      });
    });

    test('context shadows global activeSpan but global survives the call', () {
      final global = obs.startSpan('global');
      final scoped = obs.startSpan('scoped');
      obs.activeSpan = global;
      obs.runInSpan(scoped, () {
        expect(obs.activeSpan, same(scoped));
      });
      expect(obs.activeSpan, same(global));
      obs.activeSpan = null;
    });

    test('runInContext without a span leaves activeSpan null until set', () {
      obs.runInContext(() {
        expect(obs.activeSpan, isNull);
        final span = obs.startSpan('lazy');
        obs.activeSpan = span;
        expect(obs.activeSpan, same(span));
      });
      expect(obs.activeSpan, isNull);
    });
  });
}
