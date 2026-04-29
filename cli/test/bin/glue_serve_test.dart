/// End-to-end tests for `glue serve --stdio`.
///
/// Spawns the bin entrypoint, writes JSON-RPC messages on stdin, and
/// asserts the handshake response on stdout. Exercises the same code
/// path an editor would hit when launching glue as an ACP agent.
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
  test('responds to initialize with agentInfo + protocolVersion', () async {
    final lines = await _serveAndCollect([_initializeRequest], 1);
    expect(lines, hasLength(1));
    final response = jsonDecode(lines.single) as Map<String, Object?>;
    expect(response['jsonrpc'], '2.0');
    expect(response['id'], 1);
    final result = response['result'] as Map<String, Object?>;
    expect(result['protocolVersion'], 1);
    final agent = result['agentInfo'] as Map<String, Object?>;
    expect(agent['name'], 'glue');
    expect(agent['version'], isA<String>());
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('responds to session/new with a fresh sessionId', () async {
    final lines = await _serveAndCollect(
      [_initializeRequest, _sessionNewRequest],
      2,
    );
    expect(lines, hasLength(2));
    final newResp = jsonDecode(lines[1]) as Map<String, Object?>;
    final result = newResp['result'] as Map<String, Object?>;
    expect(result['sessionId'], isA<String>());
    expect((result['sessionId']! as String).startsWith('sess-'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('returns method-not-found for unimplemented methods', () async {
    const promptRequest =
        '{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":'
        '{"sessionId":"s","prompt":[]}}\n';
    final lines =
        await _serveAndCollect([_initializeRequest, promptRequest], 2);
    expect(lines, hasLength(2));
    final errResp = jsonDecode(lines[1]) as Map<String, Object?>;
    expect(errResp['error'], isNotNull);
    final err = errResp['error']! as Map<String, Object?>;
    expect(err['code'], -32601); // methodNotFound
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Spawns `dart run bin/glue.dart serve --stdio`, writes [requests] to
/// stdin, then reads stdout until [expectedLines] newline-terminated
/// messages have been received. Closes stdin to let the server exit.
Future<List<String>> _serveAndCollect(
  List<String> requests,
  int expectedLines,
) async {
  final process = await Process.start(
    'dart',
    ['run', 'bin/glue.dart', 'serve', '--stdio'],
    workingDirectory: Directory.current.path,
    runInShell: true,
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

  await readyForExit.future
      .timeout(const Duration(seconds: 45), onTimeout: () {});
  await process.stdin.close();
  await sub.cancel();
  await process.exitCode;
  return received;
}
