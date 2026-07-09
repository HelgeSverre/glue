import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:glue_core/glue_core.dart';
import 'package:glue_runtimes/daytona.dart';
import 'package:glue_runtimes/src/daytona/client.dart';
import 'package:glue_runtimes/src/daytona/executor.dart';

void main() {
  const config = DaytonaConfig(apiKey: 'sk-test');
  final sandbox = DaytonaSandbox(
    id: 'sb-abc',
    toolboxBaseUrl: 'https://proxy.app-eu.daytona.io/toolbox',
  );

  group('DaytonaExecutor.runCapture', () {
    test('routes through execCapture and tags runtimeId/sessionId', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'result': 'hello\n', 'exitCode': 0}),
          200,
        ),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      final executor = DaytonaExecutor(client: client, sandbox: sandbox);
      final result = await executor.runCapture('echo hello');
      expect(result.exitCode, 0);
      expect(result.stdout, 'hello\n');
      expect(
        result.stderr,
        '',
        reason: 'Daytona returns combined output; stderr stays empty',
      );
      expect(result.runtimeId, 'daytona');
      expect(result.sessionId, 'sb-abc');
    });

    test(
      'propagates exec timeout as milliseconds in the request body',
      () async {
        http.BaseRequest? captured;
        final mock = MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'result': '', 'exitCode': 0}), 200);
        });
        final client = DaytonaClient(config: config, httpClient: mock);
        final executor = DaytonaExecutor(client: client, sandbox: sandbox);
        await executor.runCapture(
          'sleep 1',
          timeout: const Duration(seconds: 2),
        );
        final body =
            jsonDecode((captured! as http.Request).body)
                as Map<String, dynamic>;
        expect(
          body['timeout'],
          2000,
          reason: 'Daytona expects milliseconds, not seconds',
        );
      },
    );

    test('emits Started → Completed when given an event sink', () async {
      final mock = MockClient(
        (_) async =>
            http.Response(jsonEncode({'result': 'hi\n', 'exitCode': 0}), 200),
      );
      final events = <RuntimeEvent>[];
      final client = DaytonaClient(config: config, httpClient: mock);
      final executor = DaytonaExecutor(
        client: client,
        sandbox: sandbox,
        eventSink: events.add,
      );
      await executor.runCapture('echo hi');
      expect(events, hasLength(2));
      final started = events.first as RuntimeCommandStarted;
      expect(started.runtimeId, 'daytona');
      expect(started.sandboxId, 'sb-abc');
      expect(started.runtimeCwd, '/workspace');
      final completed = events.last as RuntimeCommandCompleted;
      expect(completed.commandId, started.commandId);
      expect(completed.exitCode, 0);
    });

    test('emits Failed when the API call throws', () async {
      final mock = MockClient((_) async => http.Response('boom', 500));
      final events = <RuntimeEvent>[];
      final client = DaytonaClient(config: config, httpClient: mock);
      final executor = DaytonaExecutor(
        client: client,
        sandbox: sandbox,
        eventSink: events.add,
      );
      await expectLater(executor.runCapture('echo hi'), throwsException);
      expect(events.last, isA<RuntimeCommandFailed>());
    });
  });

  group('DaytonaExecutor.startStreaming (H13: per-command sessions)', () {
    /// A router that records every session created / exec'd / deleted so
    /// tests can assert kill isolation. Every command stays "running"
    /// (status.exitCode == null) unless its session was deleted.
    MockClient sessionTrackingClient({
      required List<String> created,
      required List<String> deleted,
    }) {
      return MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'POST' && path.endsWith('/process/session')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          created.add(body['sessionId'] as String);
          return http.Response('', 201);
        }
        if (req.method == 'POST' &&
            path.contains('/process/session/') &&
            path.endsWith('/exec')) {
          return http.Response(jsonEncode({'cmdId': 'cmd-x'}), 202);
        }
        if (req.method == 'DELETE') {
          deleted.add(path.split('/process/session/').last);
          return http.Response('', 204);
        }
        if (path.endsWith('/logs')) return http.Response('', 200);
        // Status poll — always still running.
        return http.Response(jsonEncode({'exitCode': null}), 200);
      });
    }

    test('each streaming command gets its own session', () async {
      final created = <String>[];
      final deleted = <String>[];
      final client = DaytonaClient(
        config: config,
        httpClient: sessionTrackingClient(created: created, deleted: deleted),
      );
      final executor = DaytonaExecutor(client: client, sandbox: sandbox);
      final c1 = await executor.startStreaming('long-running-1');
      final c2 = await executor.startStreaming('long-running-2');
      unawaited(c1.stdout.drain<void>());
      unawaited(c2.stdout.drain<void>());

      expect(
        created.toSet(),
        hasLength(2),
        reason: 'a shared session would create only one',
      );

      await c1.kill();
      await c2.kill();
    });

    test('killing one command does not delete a sibling\'s session', () async {
      final created = <String>[];
      final deleted = <String>[];
      final client = DaytonaClient(
        config: config,
        httpClient: sessionTrackingClient(created: created, deleted: deleted),
      );
      final executor = DaytonaExecutor(client: client, sandbox: sandbox);
      final c1 = await executor.startStreaming('cmd-1');
      final c2 = await executor.startStreaming('cmd-2');
      unawaited(c1.stdout.drain<void>());
      unawaited(c2.stdout.drain<void>());

      final session1 = created[0];
      final session2 = created[1];

      await c1.kill();

      expect(
        deleted,
        contains(session1),
        reason: 'kill must delete the killed command\'s own session',
      );
      expect(
        deleted,
        isNot(contains(session2)),
        reason:
            'killing one background command must NOT SIGTERM its siblings '
            'by deleting a shared session',
      );

      await c2.kill();
    });
  });
}
