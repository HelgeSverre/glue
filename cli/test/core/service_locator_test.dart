import 'dart:io';

import 'package:glue/src/core/environment.dart';
import 'package:glue/src/core/service_locator.dart';
import 'package:glue/src/storage/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceLocator.create', () {
    test(
        'BUG-002: does not create an empty session directory on startup '
        '(so --resume does not leave a stale empty session behind)', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('service_locator_bug002_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final env = Environment.test(
        home: tempDir.path,
        cwd: tempDir.path,
        vars: {'ANTHROPIC_API_KEY': 'sk-test-fake-for-validation'},
      );
      env.ensureDirectories();

      // Represents the user's real work they want to resume.
      final realMeta = SessionMeta(
        id: 'pre-existing-session',
        cwd: env.cwd,
        modelRef: 'anthropic/claude-sonnet-4-6',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final realStore = SessionStore(
        sessionDir: env.sessionDir(realMeta.id),
        meta: realMeta,
      );
      realStore.logEvent('user_message', {'text': 'real user work'});

      expect(
        SessionStore.listSessions(env.sessionsDir).map((s) => s.id),
        ['pre-existing-session'],
      );

      await ServiceLocator.create(environment: env);

      // After ServiceLocator.create(), no new session directory should
      // have been written to disk. The SessionStore should be created
      // lazily — either when the user resumes an existing session or
      // when they send their first message in a new session.
      expect(
        SessionStore.listSessions(env.sessionsDir).map((s) => s.id).toList(),
        ['pre-existing-session'],
        reason: 'ServiceLocator must not eagerly persist an empty session; '
            'doing so makes --continue pick up the empty session instead '
            'of the real one when --resume is used.',
      );
    });
  });
}
