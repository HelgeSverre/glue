import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:glue_runtimes/daytona.dart';
import 'package:glue_runtimes/src/daytona/client.dart';
import 'package:glue_runtimes/src/daytona/running_command.dart';

void main() {
  const config = DaytonaConfig(apiKey: 'sk-test');
  final sandbox = DaytonaSandbox(
    id: 'sb-1',
    toolboxBaseUrl: 'https://proxy.app-eu.daytona.io/toolbox',
  );

  /// Builds a MockClient that dispatches by URL — the running-command
  /// pump alternates between the `/logs` and `/command/{cmdId}`
  /// endpoints, so we need a router rather than a plain sequence.
  MockClient routedClient({
    required List<String> logsResponses,
    required List<int?> statusExitCodes,
  }) {
    var logsIdx = 0;
    var statusIdx = 0;
    return MockClient((req) async {
      if (req.url.path.endsWith('/logs')) {
        final body = logsIdx < logsResponses.length
            ? logsResponses[logsIdx++]
            : (logsResponses.isNotEmpty ? logsResponses.last : '');
        return http.Response(body, 200);
      }
      // Default: a session-command status fetch — return the next
      // exitCode in turn (null while running, int once done).
      final exit = statusIdx < statusExitCodes.length
          ? statusExitCodes[statusIdx++]
          : statusExitCodes.last;
      return http.Response(
        jsonEncode({'command': 'echo', 'exitCode': exit}),
        200,
      );
    });
  }

  group('DaytonaRunningCommand', () {
    test('polls logs + status; resolves on status exitCode', () async {
      final client = DaytonaClient(
        config: config,
        httpClient: routedClient(
          logsResponses: ['hello ', 'hello world\n', 'hello world\n'],
          // Two polls running, then exit code arrives.
          statusExitCodes: [null, null, 0],
        ),
      );
      final cmd = DaytonaRunningCommand(
        client: client,
        sandbox: sandbox,
        command: DaytonaSessionCommand(sessionId: 'bg-1', commandId: 'cmd-1'),
        pollInterval: const Duration(milliseconds: 10),
      );
      final out = await cmd.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      expect(await cmd.exitCode.timeout(const Duration(seconds: 3)), 0);
      expect(out, 'hello world\n');
    });

    test('forwards a non-zero exit code', () async {
      final client = DaytonaClient(
        config: config,
        httpClient: routedClient(
          logsResponses: ['boom\n'],
          statusExitCodes: [42],
        ),
      );
      final cmd = DaytonaRunningCommand(
        client: client,
        sandbox: sandbox,
        command: DaytonaSessionCommand(sessionId: 'bg-1', commandId: 'cmd-2'),
        pollInterval: const Duration(milliseconds: 5),
      );
      expect(await cmd.exitCode.timeout(const Duration(seconds: 3)), 42);
    });

    test('kill stops polling and resolves exitCode to -1', () async {
      // Stay in the "still running" state forever; kill should
      // resolve us to -1 via the kill path.
      final client = DaytonaClient(
        config: config,
        httpClient: MockClient((req) async {
          if (req.method == 'DELETE') return http.Response('', 204);
          if (req.url.path.endsWith('/logs')) {
            return http.Response('partial', 200);
          }
          return http.Response(jsonEncode({'exitCode': null}), 200);
        }),
      );
      final cmd = DaytonaRunningCommand(
        client: client,
        sandbox: sandbox,
        command: DaytonaSessionCommand(sessionId: 'bg-1', commandId: 'cmd-3'),
        pollInterval: const Duration(milliseconds: 5),
      );
      unawaited(cmd.stdout.drain<void>());
      unawaited(cmd.stderr.drain<void>());
      await Future.delayed(const Duration(milliseconds: 20));
      await cmd.kill();
      expect(await cmd.exitCode.timeout(const Duration(seconds: 2)), -1);
    });

    test('kill(force: true) also calls DELETE /sandbox/{id}', () async {
      // Track which paths were DELETEd — `kill(force: true)` should
      // hit both the session and the sandbox endpoints.
      final deleted = <String>[];
      final client = DaytonaClient(
        config: config,
        httpClient: MockClient((req) async {
          if (req.method == 'DELETE') {
            deleted.add(req.url.path);
            return http.Response('', 204);
          }
          if (req.url.path.endsWith('/logs')) {
            return http.Response('partial', 200);
          }
          return http.Response(jsonEncode({'exitCode': null}), 200);
        }),
      );
      final cmd = DaytonaRunningCommand(
        client: client,
        sandbox: sandbox,
        command: DaytonaSessionCommand(sessionId: 'bg-1', commandId: 'cmd-f'),
        pollInterval: const Duration(milliseconds: 5),
      );
      unawaited(cmd.stdout.drain<void>());
      unawaited(cmd.stderr.drain<void>());
      await Future.delayed(const Duration(milliseconds: 20));
      await cmd.kill(force: true);
      expect(deleted.any((p) => p.endsWith('/process/session/bg-1')), isTrue);
      expect(
        deleted.any((p) => p.endsWith('/sandbox/sb-1')),
        isTrue,
        reason: 'force-kill must stop the sandbox to honour the contract',
      );
    });
  });
}
