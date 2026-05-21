@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:glue/src/commands/session_command.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Environment env;

  setUpAll(() async {
    final which = await Process.run('which', ['git']);
    if (which.exitCode != 0) markTestSkipped('git not on PATH');
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('glue-session-cmd-');
    env = Environment.test(home: tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('listSessions', () {
    test('returns empty when no sessions dir exists', () {
      final result = listSessions(env);
      expect(result, isEmpty);
    });

    test('lists sessions sorted by start time descending', () async {
      _writeMeta(env, _meta(id: 'older', startTime: '2025-01-01T00:00:00Z'));
      _writeMeta(env, _meta(id: 'newer', startTime: '2025-02-01T00:00:00Z'));

      final result = listSessions(env);
      expect(result.map((s) => s.meta.id.value), ['newer', 'older']);
    });

    test('reports patch path + size when present on disk', () async {
      _writeMeta(env, _meta(id: 'sid', runtimeId: 'daytona'));
      final patchFile = File(
        p.join(env.sessionDir(const SessionId('sid')), 'runtime.mbox'),
      )..writeAsStringSync('From a Mon\nSubject: x\n\nbody\n');

      final result = listSessions(env);
      expect(result.first.patchPath, patchFile.path);
      expect(result.first.patchSizeBytes, patchFile.lengthSync());
    });

    test('skips sessions with corrupt meta', () async {
      final dir = Directory(p.join(env.sessionsDir, 'broken'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'meta.json')).writeAsStringSync('{not json');
      _writeMeta(env, _meta(id: 'good'));

      final result = listSessions(env);
      expect(result.map((s) => s.meta.id.value), ['good']);
    });
  });

  group('applySessionPatch', () {
    test('returns ok=false when patch is missing', () async {
      _writeMeta(env, _meta(id: 'sid'));
      final session = listSessions(env).first;
      final result = await applySessionPatch(
        session: session,
        targetDir: tmp.path,
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('no runtime.mbox'));
    });

    test('refuses to apply truncated patches', () async {
      _writeMeta(env, _meta(id: 'sid', runtimeId: 'daytona'));
      final truncated = File(
        p.join(
          env.sessionDir(const SessionId('sid')),
          'runtime.mbox.truncated',
        ),
      )..writeAsStringSync('partial');

      final session = listSessions(env).first;
      expect(session.patchPath, truncated.path);
      final result = await applySessionPatch(
        session: session,
        targetDir: tmp.path,
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('truncated'));
    });
  });
}

SessionMeta _meta({required String id, String? startTime, String? runtimeId}) {
  return SessionMeta(
    id: SessionId(id),
    cwd: '/x',
    modelRef: 'anthropic/claude',
    startTime: DateTime.parse(startTime ?? '2025-05-19T00:00:00Z'),
    runtimeId: runtimeId,
  );
}

void _writeMeta(Environment env, SessionMeta meta) {
  final dir = Directory(env.sessionDir(meta.id))..createSync(recursive: true);
  File(
    p.join(dir.path, 'meta.json'),
  ).writeAsStringSync(jsonEncode(meta.toJson()));
}
