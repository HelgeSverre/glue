import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:glue_runtimes/daytona.dart';
import 'package:glue_runtimes/src/daytona/client.dart';

void main() {
  const config = DaytonaConfig(apiKey: 'sk-test');
  // Shared sandbox stub used by every toolbox-side test. The
  // `toolboxBaseUrl` here exercises the EU-region routing path.
  final sandbox = DaytonaSandbox(
    id: 'sb-123',
    toolboxBaseUrl: 'https://proxy.app-eu.daytona.io/toolbox',
  );

  group('DaytonaClient.createSandbox', () {
    test(
      'POSTs /sandbox with empty body when no snapshot configured',
      () async {
        http.BaseRequest? captured;
        final mock = MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'id': 'sb-123',
              'state': 'started',
              'toolboxProxyUrl': 'https://proxy.app-eu.daytona.io/toolbox',
            }),
            200,
          );
        });
        final client = DaytonaClient(config: config, httpClient: mock);
        final result = await client.createSandbox();
        expect(result.id, 'sb-123');
        expect(result.state, 'started');
        expect(
          result.toolboxBaseUrl,
          'https://proxy.app-eu.daytona.io/toolbox',
        );
        final body =
            jsonDecode((captured! as http.Request).body)
                as Map<String, dynamic>;
        expect(
          body,
          isEmpty,
          reason:
              'glue must not send cpu/memory/disk — Daytona rejects '
              'those alongside the default snapshot.',
        );
      },
    );

    test('POSTs /sandbox with snapshot when configured', () async {
      http.BaseRequest? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'id': 'sb-9',
            'toolboxProxyUrl': 'https://proxy.app.daytona.io/toolbox',
          }),
          200,
        );
      });
      final client = DaytonaClient(
        config: const DaytonaConfig(apiKey: 'sk-test', snapshot: 'my-snap'),
        httpClient: mock,
      );
      await client.createSandbox();
      final body =
          jsonDecode((captured! as http.Request).body) as Map<String, dynamic>;
      expect(body['snapshot'], 'my-snap');
    });

    test('uses the toolboxBaseUrlOverride when set', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'id': 'sb-x',
            // Server returns the real per-sandbox URL...
            'toolboxProxyUrl': 'https://proxy.app-eu.daytona.io/toolbox',
          }),
          200,
        ),
      );
      final client = DaytonaClient(
        config: const DaytonaConfig(
          apiKey: 'sk-test',
          // ...but we force traffic through this override.
          toolboxBaseUrlOverride: 'https://proxy.staging/toolbox',
        ),
        httpClient: mock,
      );
      final result = await client.createSandbox();
      expect(result.toolboxBaseUrl, 'https://proxy.app-eu.daytona.io/toolbox');
    });

    test('raises RuntimeApiException on a non-2xx response', () async {
      final mock = MockClient((_) async => http.Response('rate limit', 429));
      final client = DaytonaClient(config: config, httpClient: mock);
      await expectLater(
        client.createSandbox(),
        throwsA(
          isA<RuntimeApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.endpoint, 'endpoint', 'create_sandbox'),
        ),
      );
    });

    test('raises when toolboxProxyUrl is missing from the response', () async {
      final mock = MockClient(
        (_) async => http.Response(jsonEncode({'id': 'sb-1'}), 200),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      await expectLater(
        client.createSandbox(),
        throwsA(
          isA<RuntimeApiException>().having(
            (e) => e.message,
            'message',
            contains('toolboxProxyUrl'),
          ),
        ),
      );
    });
  });

  group('DaytonaClient.execCapture', () {
    test('POSTs /process/execute on the per-sandbox toolbox host', () async {
      http.BaseRequest? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({'result': 'hello world\n', 'exitCode': 0}),
          200,
        );
      });
      final client = DaytonaClient(config: config, httpClient: mock);
      final r = await client.execCapture(
        sandbox,
        'echo hello',
        timeout: const Duration(seconds: 5),
      );
      expect(r.exitCode, 0);
      expect(r.result, 'hello world\n');
      expect(
        captured!.url.toString(),
        'https://proxy.app-eu.daytona.io/toolbox/sb-123/process/execute',
      );
      final body =
          jsonDecode((captured! as http.Request).body) as Map<String, dynamic>;
      expect(body['command'], 'echo hello');
      expect(body['timeout'], 5000);
    });

    test('handles a non-zero exit code without raising', () async {
      final mock = MockClient(
        (_) async =>
            http.Response(jsonEncode({'result': 'nope\n', 'exitCode': 1}), 200),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      final r = await client.execCapture(sandbox, 'false');
      expect(r.exitCode, 1);
      expect(r.result, 'nope\n');
    });
  });

  group('DaytonaClient session API', () {
    test('createSession POSTs /process/session with sessionId', () async {
      http.BaseRequest? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('', 201);
      });
      final client = DaytonaClient(config: config, httpClient: mock);
      await client.createSession(sandbox, 'bg-1');
      expect(captured!.url.path, '/toolbox/sb-123/process/session');
      final body =
          jsonDecode((captured! as http.Request).body) as Map<String, dynamic>;
      expect(body['sessionId'], 'bg-1');
    });

    test('executeSessionCommand returns cmdId', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'cmdId': 'cmd-42',
            'output': null,
            'stdout': null,
            'stderr': null,
            'exitCode': null,
          }),
          202,
        ),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      final cmd = await client.executeSessionCommand(
        sandbox,
        'bg-1',
        'sleep 5',
        runAsync: true,
      );
      expect(cmd.commandId, 'cmd-42');
      expect(cmd.sessionId, 'bg-1');
    });

    test('getSessionCommandLogs returns the raw body string', () async {
      final mock = MockClient(
        (_) async => http.Response('hello\nworld\n', 200),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      final logs = await client.getSessionCommandLogs(
        sandbox,
        'bg-1',
        'cmd-42',
      );
      expect(logs, 'hello\nworld\n');
    });

    test('getSessionCommandStatus parses exitCode (null until done)', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'command': 'echo hi', 'exitCode': null}),
          200,
        ),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      final s = await client.getSessionCommandStatus(sandbox, 'bg-1', 'cmd-42');
      expect(s.exitCode, isNull);
    });

    test(
      'getSessionCommandStatus returns the int exitCode once done',
      () async {
        final mock = MockClient(
          (_) async => http.Response(
            jsonEncode({'command': 'echo hi', 'exitCode': 0}),
            200,
          ),
        );
        final client = DaytonaClient(config: config, httpClient: mock);
        final s = await client.getSessionCommandStatus(
          sandbox,
          'bg-1',
          'cmd-42',
        );
        expect(s.exitCode, 0);
      },
    );

    test('deleteSession DELETEs /process/session/<sid>', () async {
      http.BaseRequest? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('', 204);
      });
      final client = DaytonaClient(config: config, httpClient: mock);
      await client.deleteSession(sandbox, 'bg-1');
      expect(captured!.method, 'DELETE');
      expect(captured!.url.path, '/toolbox/sb-123/process/session/bg-1');
    });
  });

  group('DaytonaClient.readFile / writeFile', () {
    test('reads file bytes from /files/download?path=...', () async {
      http.BaseRequest? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response.bytes([1, 2, 3], 200);
      });
      final client = DaytonaClient(config: config, httpClient: mock);
      final bytes = await client.readFile(sandbox, '/workspace/foo.txt');
      expect(bytes, [1, 2, 3]);
      expect(captured!.url.path, '/toolbox/sb-123/files/download');
      expect(captured!.url.queryParameters['path'], '/workspace/foo.txt');
    });

    test('writes bytes via multipart upload', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('', 200);
      });
      final client = DaytonaClient(config: config, httpClient: mock);
      await client.writeFile(sandbox, '/workspace/x.txt', utf8.encode('hi'));
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/toolbox/sb-123/files/upload');
      expect(captured!.url.queryParameters['path'], '/workspace/x.txt');
      expect(captured!.headers['content-type'] ?? '', startsWith('multipart/'));
      expect(captured!.body, contains('hi'));
    });

    test('readFile translates HTTP 404 into RuntimeApiException', () async {
      final mock = MockClient((_) async => http.Response('not found', 404));
      final client = DaytonaClient(config: config, httpClient: mock);
      await expectLater(
        client.readFile(sandbox, '/missing'),
        throwsA(
          isA<RuntimeApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });
  });

  group('DaytonaClient.listDir / stat', () {
    test(
      'list uses /files/ (trailing slash to avoid the 301 redirect)',
      () async {
        http.BaseRequest? captured;
        final mock = MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode([
              {'name': 'a.txt', 'isDir': false, 'size': 12},
              {'name': 'sub', 'isDir': true, 'size': 0},
            ]),
            200,
          );
        });
        final client = DaytonaClient(config: config, httpClient: mock);
        final entries = await client.listDir(sandbox, '/workspace');
        expect(entries, hasLength(2));
        expect(captured!.url.path, '/toolbox/sb-123/files/');
        expect(captured!.url.queryParameters['path'], '/workspace');
      },
    );

    test('stat returns null on 404', () async {
      final mock = MockClient((_) async => http.Response('not found', 404));
      final client = DaytonaClient(config: config, httpClient: mock);
      expect(await client.stat(sandbox, '/missing'), isNull);
    });

    test('stat parses size + isDir', () async {
      final mock = MockClient(
        (_) async =>
            http.Response(jsonEncode({'size': 42, 'isDir': false}), 200),
      );
      final client = DaytonaClient(config: config, httpClient: mock);
      final stat = await client.stat(sandbox, '/workspace/a.txt');
      expect(stat!.size, 42);
      expect(stat.isDirectory, isFalse);
    });
  });
}
