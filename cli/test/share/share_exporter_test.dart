import 'dart:io';

import 'package:glue/src/share/share_exporter.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('ShareExporter', () {
    late Directory tempDir;
    late String sessionDir;
    late SessionStore store;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('session_share_exporter_test_');
      sessionDir = '${tempDir.path}/session-1';
      store = SessionStore(
        sessionDir: sessionDir,
        meta: SessionMeta(
          id: 'session-1',
          cwd: '/tmp/project',
          modelRef: 'anthropic/claude-sonnet-4.6',
          startTime: DateTime.parse('2026-04-22T04:00:00Z'),
          title: 'Glue',
        ),
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('writes only html by default for a session', () async {
      final exporter = ShareExporter();
      store.logEvent('user_message', {'text': 'hello'});
      store.logEvent('assistant_message', {'text': 'hi'});

      final result = await exporter.export(
        store: store,
        outputDir: tempDir.path,
        exportedAt: DateTime.parse('2026-04-22T04:20:00Z'),
      );

      expect(result.htmlPath, isNotNull);
      expect(result.markdownPath, isNull);
      expect(File(result.htmlPath!).existsSync(), isTrue);
      expect(File(result.htmlPath!).readAsStringSync(),
          contains('<!DOCTYPE html>'));
      expect(result.htmlPath, endsWith('glue-session-session-1.html'));
    });

    test('writes only requested markdown format', () async {
      final exporter = ShareExporter();
      store.logEvent('user_message', {'text': 'hello'});

      final result = await exporter.export(
        store: store,
        outputDir: tempDir.path,
        format: ShareFormat.markdown,
      );

      expect(result.markdownPath, isNotNull);
      expect(result.htmlPath, isNull);
      expect(File(result.markdownPath!).existsSync(), isTrue);
    });

    test('writes only requested html format', () async {
      final exporter = ShareExporter();
      store.logEvent('user_message', {'text': 'hello'});

      final result = await exporter.export(
        store: store,
        outputDir: tempDir.path,
        format: ShareFormat.html,
      );

      expect(result.htmlPath, isNotNull);
      expect(result.markdownPath, isNull);
      expect(File(result.htmlPath!).existsSync(), isTrue);
    });

    test('fails when there is no conversation data', () async {
      final exporter = ShareExporter();

      expect(
        () => exporter.export(store: store, outputDir: tempDir.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Current session has no conversation data.',
          ),
        ),
      );
    });
  });
}
