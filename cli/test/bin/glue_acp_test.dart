/// End-to-end tests for `glue acp --stdio`.
///
/// Spawns the bin entrypoint, writes JSON-RPC messages on stdin, and
/// asserts the responses on stdout. Exercises the full ACP server →
/// CliAcpDelegate → ServiceLocator wiring. The spawned process gets a
/// fresh `GLUE_HOME` and a fake API key so it can stand up the locator
/// without touching the user's real config or making network calls.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _initializeRequest =
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
    '{"protocolVersion":1,"clientInfo":{"name":"test"}}}\n';

const _sessionNewRequest =
    '{"jsonrpc":"2.0","id":2,"method":"session/new","params":'
    '{"cwd":"/tmp/x","mcpServers":[]}}\n';

void main() {
  test(
    'responds to initialize with truthful capabilities + auth methods',
    () async {
      final lines = await _serveAndCollect([_initializeRequest], 1);
      expect(lines, hasLength(1));
      final response = jsonDecode(lines.single) as Map<String, Object?>;
      expect(response['jsonrpc'], '2.0');
      expect(response['id'], 1);
      final result = response['result']! as Map<String, Object?>;
      expect(result['protocolVersion'], 1);
      final agent = result['agentInfo']! as Map<String, Object?>;
      expect(agent['name'], 'glue');
      expect(agent['version'], isA<String>());

      final capabilities = result['agentCapabilities']! as Map<String, Object?>;
      final promptCapabilities =
          capabilities['promptCapabilities']! as Map<String, Object?>;
      expect(promptCapabilities['image'], isTrue);
      expect(promptCapabilities['audio'], isFalse);
      expect(promptCapabilities['embeddedContext'], isFalse);
      final sessionCapabilities =
          capabilities['sessionCapabilities']! as Map<String, Object?>;
      expect(sessionCapabilities['close'], <String, Object?>{});
      expect(sessionCapabilities.containsKey('list'), isFalse);
      expect(capabilities.containsKey('mcpCapabilities'), isFalse);

      final authMethods = result['authMethods']! as List<Object?>;
      expect(authMethods, isNotEmpty);
      expect(
        authMethods.any(
          (method) =>
              method is Map &&
              method['type'] == 'terminal' &&
              method['args'] is List &&
              (method['args']! as List<Object?>).join(' ') == 'setup --check',
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'responds to session/new with a fresh sessionId',
    () async {
      final lines = await _serveAndCollect([
        _initializeRequest,
        _sessionNewRequest,
      ], 2);
      expect(lines, hasLength(2));
      final newResp = jsonDecode(lines[1]) as Map<String, Object?>;
      final result = newResp['result']! as Map<String, Object?>;
      expect(result['sessionId'], isA<String>());
      // CliAcpDelegate prefixes ids with `glue-` (vs the older `sess-` stub).
      expect((result['sessionId']! as String).startsWith('glue-'), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'session/close retires the session and later prompts return -32001',
    () async {
      const closeRequest =
          '{"jsonrpc":"2.0","id":3,"method":"session/close","params":'
          '{"sessionId":"glue-session-placeholder"}}\n';
      const promptRequest =
          '{"jsonrpc":"2.0","id":4,"method":"session/prompt","params":'
          '{"sessionId":"glue-session-placeholder","prompt":[{"type":"text","text":"hi"}]}}\n';
      final lines = await _serveAndCollectSessionCloseFlow(
        closeRequest: closeRequest,
        promptRequest: promptRequest,
      );
      expect(lines, hasLength(4));
      final closeResp = jsonDecode(lines[2]) as Map<String, Object?>;
      expect(closeResp['id'], 3);
      expect(closeResp['result'], <String, Object?>{});

      final errResp = jsonDecode(lines[3]) as Map<String, Object?>;
      expect(errResp['error'], isNotNull);
      final err = errResp['error']! as Map<String, Object?>;
      expect(err['code'], -32001);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

/// Spawns `dart run bin/glue.dart acp --stdio`, writes [requests] to
/// stdin, then reads stdout until [expectedLines] messages have been
/// received. Provides a fake API key + isolated `GLUE_HOME` so the
/// real ServiceLocator can construct without hitting the user's config
/// or making network calls.
Future<List<String>> _serveAndCollect(
  List<String> requests,
  int expectedLines,
) async {
  final harness = await _AcpStdioHarness.start();
  await harness.sendAll(requests);
  await harness.waitForLines(expectedLines);
  return harness.close();
}

Future<List<String>> _serveAndCollectSessionCloseFlow({
  required String closeRequest,
  required String promptRequest,
}) async {
  final harness = await _AcpStdioHarness.start();

  await harness.sendAll([_initializeRequest, _sessionNewRequest]);
  await harness.waitForLines(2);
  final sessionId = harness.sessionIdFromResponse(1);

  await harness.sendAll([
    closeRequest.replaceAll('glue-session-placeholder', sessionId),
    promptRequest.replaceAll('glue-session-placeholder', sessionId),
  ]);
  await harness.waitForLines(4);

  return harness.close();
}

class _AcpStdioHarness {
  _AcpStdioHarness._({required this.process, required this.received});

  final Process process;
  final List<String> received;

  static Future<_AcpStdioHarness> start() async {
    final tmp = Directory.systemTemp.createTempSync('glue_serve_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final process = await Process.start(
      'dart',
      ['run', '--verbosity=error', 'bin/glue.dart', 'acp', '--stdio'],
      workingDirectory: _cliPackageRoot(),
      runInShell: true,
      environment: {
        'GLUE_HOME': tmp.path,
        'ANTHROPIC_API_KEY': 'sk-test-fake-for-validation',
      },
    );

    final received = <String>[];
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.isNotEmpty) {
            received.add(line);
          }
        });
    addTearDown(() async {
      await stdoutSub.cancel();
    });

    return _AcpStdioHarness._(process: process, received: received);
  }

  Future<void> sendAll(Iterable<String> requests) async {
    for (final request in requests) {
      process.stdin.write(request);
    }
    await process.stdin.flush();
  }

  Future<void> waitForLines(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (received.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Timed out waiting for $count stdout lines.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  String sessionIdFromResponse(int responseIndex) {
    final response =
        jsonDecode(received[responseIndex]) as Map<String, Object?>;
    return (response['result']! as Map<String, Object?>)['sessionId']!
        as String;
  }

  Future<List<String>> close() async {
    await process.stdin.close();
    await process.exitCode;
    return received;
  }
}

String _cliPackageRoot() {
  final cwd = Directory.current.path;
  if (File('$cwd/bin/glue.dart').existsSync()) return cwd;
  if (File('$cwd/cli/bin/glue.dart').existsSync()) return '$cwd/cli';
  throw StateError('Could not locate cli/bin/glue.dart from $cwd');
}
