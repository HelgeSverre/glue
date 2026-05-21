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
    'responds to initialize with agentInfo + protocolVersion',
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
    'session/prompt against an unknown session returns -32001',
    () async {
      const promptRequest =
          '{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":'
          '{"sessionId":"unknown","prompt":[{"type":"text","text":"hi"}]}}\n';
      final lines = await _serveAndCollect([
        _initializeRequest,
        promptRequest,
      ], 2);
      expect(lines, hasLength(2));
      final errResp = jsonDecode(lines[1]) as Map<String, Object?>;
      expect(errResp['error'], isNotNull);
      final err = errResp['error']! as Map<String, Object?>;
      // Glue-reserved code for sessionNotFound.
      expect(err['code'], -32001);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

/// Spawns `dart run bin/glue.dart serve --stdio`, writes [requests] to
/// stdin, then reads stdout until [expectedLines] messages have been
/// received. Provides a fake API key + isolated `GLUE_HOME` so the
/// real ServiceLocator can construct without hitting the user's config
/// or making network calls.
Future<List<String>> _serveAndCollect(
  List<String> requests,
  int expectedLines,
) async {
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
  final readyForExit = Completer<void>();
  final sub = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.isEmpty) return;
        received.add(line);
        if (received.length >= expectedLines && !readyForExit.isCompleted) {
          readyForExit.complete();
        }
      });

  for (final req in requests) {
    process.stdin.write(req);
  }
  await process.stdin.flush();

  await readyForExit.future.timeout(
    const Duration(seconds: 45),
    onTimeout: () {},
  );
  await process.stdin.close();
  await sub.cancel();
  await process.exitCode;
  return received;
}

String _cliPackageRoot() {
  final cwd = Directory.current.path;
  if (File('$cwd/bin/glue.dart').existsSync()) return cwd;
  if (File('$cwd/cli/bin/glue.dart').existsSync()) return '$cwd/cli';
  throw StateError('Could not locate cli/bin/glue.dart from $cwd');
}
