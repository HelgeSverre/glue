import 'dart:convert';
import 'dart:io';

import 'package:glue/glue.dart';
import 'package:glue/src/commands/trace_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Map<String, dynamic> _span({
  required String name,
  required String kind,
  required String traceId,
  required String start,
  String? end,
  String? parentSpanId,
  Map<String, dynamic>? attributes,
}) {
  return {
    'trace_id': traceId,
    'span_id': '${traceId}_${name.hashCode.toRadixString(16)}',
    'parent_span_id': ?parentSpanId,
    'name': name,
    'kind': kind,
    'start_time': start,
    'end_time': end,
    'duration_ms': end == null
        ? 0
        : DateTime.parse(end).difference(DateTime.parse(start)).inMilliseconds,
    'status_code': 'unset',
    'attributes': attributes ?? const {},
  };
}

({Environment env, String sessionId}) _fixture(
  Directory home, {
  required DateTime sessionStart,
  required DateTime sessionEnd,
  required String dateForLog,
  required List<Map<String, dynamic>> spans,
}) {
  final env = Environment.test(home: home.path);
  const sessionId = 'sess-fixture';

  final sessionDir = Directory(p.join(env.sessionsDir, sessionId))
    ..createSync(recursive: true);
  File(p.join(sessionDir.path, 'meta.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schema_version': 3,
      'id': sessionId,
      'cwd': '/tmp',
      'model_ref': 'anthropic/claude-opus',
      'start_time': sessionStart.toUtc().toIso8601String(),
      'end_time': sessionEnd.toUtc().toIso8601String(),
    }),
  );

  Directory(env.logsDir).createSync(recursive: true);
  final logFile = File(p.join(env.logsDir, 'spans-$dateForLog.jsonl'));
  logFile.writeAsStringSync(spans.map(jsonEncode).join('\n'));

  return (env: env, sessionId: sessionId);
}

void main() {
  group('exportSessionTrace', () {
    test('filters spans by session time window and writes envelope', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));

      final start = DateTime.utc(2026, 5, 27, 10, 0, 0);
      final end = DateTime.utc(2026, 5, 27, 10, 5, 0);

      final inWindow = _span(
        name: 'agent.turn',
        kind: 'agent',
        traceId: 'trace-A',
        start: '2026-05-27T10:01:00.000Z',
        end: '2026-05-27T10:01:02.000Z',
      );
      final outOfWindow = _span(
        name: 'old.turn',
        kind: 'agent',
        traceId: 'trace-OLD',
        start: '2026-05-27T09:00:00.000Z',
        end: '2026-05-27T09:00:01.000Z',
      );

      final f = _fixture(
        home,
        sessionStart: start,
        sessionEnd: end,
        dateForLog: '2026-05-27',
        spans: [inWindow, outOfWindow],
      );

      final result = exportSessionTrace(env: f.env, sessionId: f.sessionId);

      expect(result.spanCount, 1);
      expect(result.droppedInFlight, 0);
      expect(result.scannedLogFiles, hasLength(1));
      expect(File(result.outputPath).existsSync(), isTrue);

      final decoded =
          jsonDecode(File(result.outputPath).readAsStringSync())
              as Map<String, dynamic>;
      final names = (decoded['traceEvents'] as List)
          .whereType<Map<String, dynamic>>()
          .where((e) => e['ph'] == 'X')
          .map((e) => e['name'])
          .toList();
      expect(names, ['agent.turn']);
      expect((decoded['otherData'] as Map)['glue.sessionId'], f.sessionId);
    });

    test('counts in-flight spans separately from completed ones', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));

      final start = DateTime.utc(2026, 5, 27, 10, 0, 0);
      final end = DateTime.utc(2026, 5, 27, 10, 5, 0);

      final complete = _span(
        name: 'tool.bash',
        kind: 'tool',
        traceId: 'trace-A',
        start: '2026-05-27T10:01:00.000Z',
        end: '2026-05-27T10:01:01.000Z',
      );
      final inflight = _span(
        name: 'tool.bash',
        kind: 'tool',
        traceId: 'trace-B',
        start: '2026-05-27T10:02:00.000Z',
        end: null,
      );

      final f = _fixture(
        home,
        sessionStart: start,
        sessionEnd: end,
        dateForLog: '2026-05-27',
        spans: [complete, inflight],
      );

      final result = exportSessionTrace(env: f.env, sessionId: f.sessionId);
      expect(result.spanCount, 1);
      expect(result.droppedInFlight, 1);
    });

    test('writes to custom outputPath when provided', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));

      final f = _fixture(
        home,
        sessionStart: DateTime.utc(2026, 5, 27, 10),
        sessionEnd: DateTime.utc(2026, 5, 27, 10, 5),
        dateForLog: '2026-05-27',
        spans: [
          _span(
            name: 'agent.turn',
            kind: 'agent',
            traceId: 'trace-A',
            start: '2026-05-27T10:01:00.000Z',
            end: '2026-05-27T10:01:02.000Z',
          ),
        ],
      );

      final custom = p.join(home.path, 'custom-trace.json');
      final result = exportSessionTrace(
        env: f.env,
        sessionId: f.sessionId,
        outputPath: custom,
      );
      expect(result.outputPath, custom);
      expect(File(custom).existsSync(), isTrue);
    });

    test('throws TraceExportException for unknown session', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      Directory(env.sessionsDir).createSync(recursive: true);

      expect(
        () => exportSessionTrace(env: env, sessionId: 'nope'),
        throwsA(isA<TraceExportException>()),
      );
    });

    test('produces a usable result even when no spans on disk', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));

      final f = _fixture(
        home,
        sessionStart: DateTime.utc(2026, 5, 27, 10),
        sessionEnd: DateTime.utc(2026, 5, 27, 10, 5),
        dateForLog: '2026-05-27',
        spans: const [],
      );

      final result = exportSessionTrace(env: f.env, sessionId: f.sessionId);
      expect(result.spanCount, 0);
      final decoded =
          jsonDecode(File(result.outputPath).readAsStringSync())
              as Map<String, dynamic>;
      // Envelope still emits process_name M event.
      expect(decoded['traceEvents'], isA<List<dynamic>>());
    });
  });

  group('findLatestSession', () {
    test('returns the most recently started session', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);

      void writeMeta(String id, DateTime start) {
        final dir = Directory(p.join(env.sessionsDir, id))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'meta.json')).writeAsStringSync(
          jsonEncode({
            'schema_version': 3,
            'id': id,
            'cwd': '/tmp',
            'model_ref': 'anthropic/claude-opus',
            'start_time': start.toUtc().toIso8601String(),
          }),
        );
      }

      writeMeta('older', DateTime.utc(2026, 5, 26));
      writeMeta('newer', DateTime.utc(2026, 5, 27));

      final latest = findLatestSession(env);
      expect(latest?.id.value, 'newer');
    });

    test('returns null when sessions dir is empty', () {
      final home = Directory.systemTemp.createTempSync('glue_trace_');
      addTearDown(() => home.deleteSync(recursive: true));
      final env = Environment.test(home: home.path);
      expect(findLatestSession(env), isNull);
    });
  });
}
