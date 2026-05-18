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
    test('routes through execCapture and tags runtimeId/sessionId',
        () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({'result': 'hello\n', 'exitCode': 0}),
            200,
          ));
      final client = DaytonaClient(config: config, httpClient: mock);
      final executor = DaytonaExecutor(client: client, sandbox: sandbox);
      final result = await executor.runCapture('echo hello');
      expect(result.exitCode, 0);
      expect(result.stdout, 'hello\n');
      expect(result.stderr, '',
          reason: 'Daytona returns combined output; stderr stays empty');
      expect(result.runtimeId, 'daytona');
      expect(result.sessionId, 'sb-abc');
    });

    test('propagates exec timeout as milliseconds in the request body',
        () async {
      http.BaseRequest? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({'result': '', 'exitCode': 0}),
          200,
        );
      });
      final client = DaytonaClient(config: config, httpClient: mock);
      final executor = DaytonaExecutor(client: client, sandbox: sandbox);
      await executor.runCapture('sleep 1',
          timeout: const Duration(seconds: 2));
      final body =
          jsonDecode((captured! as http.Request).body) as Map<String, dynamic>;
      expect(body['timeout'], 2000,
          reason: 'Daytona expects milliseconds, not seconds');
    });

    test('emits Started → Completed when given an event sink', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({'result': 'hi\n', 'exitCode': 0}),
            200,
          ));
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
}
