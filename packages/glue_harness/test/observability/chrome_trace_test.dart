import 'dart:convert';

import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;

List<dynamic> _events(String s) => _decode(s)['traceEvents'] as List<dynamic>;

Map<String, dynamic> _span({
  required String name,
  required String kind,
  required String traceId,
  String? parentSpanId,
  required String start,
  String? end,
  Map<String, dynamic>? attributes,
  List<Map<String, dynamic>>? events,
  String statusCode = 'unset',
}) {
  final spanId =
      '${traceId.substring(0, 6)}${name.hashCode.toRadixString(16).padLeft(2, '0').substring(0, 2)}';
  return {
    'trace_id': traceId,
    'span_id': spanId,
    'parent_span_id': ?parentSpanId,
    'name': name,
    'kind': kind,
    'start_time': start,
    'end_time': end,
    'duration_ms': end == null
        ? 0
        : DateTime.parse(end).difference(DateTime.parse(start)).inMilliseconds,
    'status_code': statusCode,
    'events': ?events,
    'attributes': attributes ?? const {},
  };
}

void main() {
  group('spansToChromeTrace', () {
    test('emits a valid envelope with sessionId metadata', () {
      final json = spansToChromeTrace([], sessionId: 'sess-1');
      final decoded = _decode(json);

      expect(decoded['traceEvents'], isA<List<dynamic>>());
      expect(decoded['displayTimeUnit'], 'ms');
      final other = decoded['otherData'] as Map<String, dynamic>;
      expect(other['glue.sessionId'], 'sess-1');
    });

    test('single completed span -> one Complete (X) event', () {
      final span = _span(
        name: 'agent.turn',
        kind: 'agent',
        traceId: 'trace-1',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:01.500Z',
        attributes: {'llm.model_name': 'anthropic/claude-opus'},
      );

      final json = spansToChromeTrace([span], sessionId: 'sess');
      final xs = _events(
        json,
      ).whereType<Map<String, dynamic>>().where((e) => e['ph'] == 'X').toList();

      expect(xs, hasLength(1));
      final e = xs.single;
      expect(e['name'], 'agent.turn');
      expect(e['cat'], 'agent');
      expect(e['pid'], 1);
      expect(e['ts'], isA<int>());
      expect(e['dur'], 1500 * 1000); // 1.5s in microseconds
      expect(
        (e['args'] as Map)['data'],
        containsPair('llm.model_name', 'anthropic/claude-opus'),
      );
    });

    test('spans with same trace_id share a thread (tid)', () {
      final parent = _span(
        name: 'agent.iteration',
        kind: 'agent',
        traceId: 'trace-A',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:02.000Z',
      );
      final child = _span(
        name: 'tool.bash',
        kind: 'tool',
        traceId: 'trace-A',
        parentSpanId: parent['span_id'] as String,
        start: '2026-05-27T10:00:00.500Z',
        end: '2026-05-27T10:00:01.500Z',
      );

      final json = spansToChromeTrace([parent, child], sessionId: 'sess');
      final xs = _events(
        json,
      ).whereType<Map<String, dynamic>>().where((e) => e['ph'] == 'X').toList();

      expect(xs, hasLength(2));
      expect(xs.first['tid'], xs.last['tid']);
    });

    test('spans with different trace_ids get different tids', () {
      final a = _span(
        name: 'agent.turn',
        kind: 'agent',
        traceId: 'trace-A',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:01.000Z',
      );
      final b = _span(
        name: 'session.title.generate',
        kind: 'session',
        traceId: 'trace-B',
        start: '2026-05-27T10:00:01.000Z',
        end: '2026-05-27T10:00:01.500Z',
      );

      final json = spansToChromeTrace([a, b], sessionId: 'sess');
      final xs = _events(
        json,
      ).whereType<Map<String, dynamic>>().where((e) => e['ph'] == 'X').toList();

      expect({xs[0]['tid'], xs[1]['tid']}, hasLength(2));
    });

    test('spans missing end_time are dropped', () {
      final inflight = _span(
        name: 'tool.bash',
        kind: 'tool',
        traceId: 'trace-1',
        start: '2026-05-27T10:00:00.000Z',
        end: null,
      );

      final json = spansToChromeTrace([inflight], sessionId: 'sess');
      final xs = _events(
        json,
      ).whereType<Map<String, dynamic>>().where((e) => e['ph'] == 'X').toList();

      expect(xs, isEmpty);
    });

    test('span events become Instant (i) events on the same thread', () {
      final span = _span(
        name: 'agent.turn',
        kind: 'agent',
        traceId: 'trace-1',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:01.000Z',
        events: [
          {
            'name': 'permission_requested',
            'timestamp': '2026-05-27T10:00:00.500Z',
            'attributes': {'tool': 'bash'},
          },
        ],
      );

      final json = spansToChromeTrace([span], sessionId: 'sess');
      final events = _events(json).whereType<Map<String, dynamic>>().toList();
      final xEvent = events.firstWhere((e) => e['ph'] == 'X');
      final iEvents = events.where((e) => e['ph'] == 'i').toList();

      expect(iEvents, hasLength(1));
      final i = iEvents.single;
      expect(i['name'], 'permission_requested');
      expect(i['tid'], xEvent['tid']);
      expect(i['s'], 't'); // thread-scoped instant
      expect((i['args'] as Map)['data'], containsPair('tool', 'bash'));
    });

    test('emits process_name and thread_name metadata (M) events', () {
      final span = _span(
        name: 'agent.turn',
        kind: 'agent',
        traceId: 'trace-1',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:01.000Z',
      );

      final json = spansToChromeTrace([span], sessionId: 'sess');
      final ms = _events(
        json,
      ).whereType<Map<String, dynamic>>().where((e) => e['ph'] == 'M').toList();

      expect(
        ms.any(
          (m) =>
              m['name'] == 'process_name' &&
              (m['args'] as Map)['name'] == 'glue',
        ),
        isTrue,
      );
      expect(
        ms.any(
          (m) =>
              m['name'] == 'thread_name' &&
              (m['args'] as Map)['name'] == 'agent.turn',
        ),
        isTrue,
      );
    });

    test('error status surfaces in args.glue.status', () {
      final span = _span(
        name: 'tool.bash',
        kind: 'tool',
        traceId: 'trace-1',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:00.100Z',
        statusCode: 'error',
      );

      final json = spansToChromeTrace([span], sessionId: 'sess');
      final x = _events(
        json,
      ).whereType<Map<String, dynamic>>().firstWhere((e) => e['ph'] == 'X');

      final args = (x['args'] as Map)['data'] as Map;
      expect(args['glue.status'], 'error');
    });

    test('thread name is the root span (no parent) of the trace', () {
      final root = _span(
        name: 'agent.iteration',
        kind: 'agent',
        traceId: 'trace-A',
        start: '2026-05-27T10:00:00.000Z',
        end: '2026-05-27T10:00:02.000Z',
      );
      final child = _span(
        name: 'tool.bash',
        kind: 'tool',
        traceId: 'trace-A',
        parentSpanId: root['span_id'] as String,
        start: '2026-05-27T10:00:00.500Z',
        end: '2026-05-27T10:00:01.500Z',
      );

      final json = spansToChromeTrace(
        [child, root], // intentionally out of order
        sessionId: 'sess',
      );
      final threadNames = _events(json)
          .whereType<Map<String, dynamic>>()
          .where((m) => m['ph'] == 'M' && m['name'] == 'thread_name')
          .map((m) => (m['args'] as Map)['name'] as String)
          .toList();

      expect(threadNames, contains('agent.iteration'));
      expect(threadNames, isNot(contains('tool.bash')));
    });
  });
}
