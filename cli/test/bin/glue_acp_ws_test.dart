/// End-to-end tests for `glue acp --port N` (ACP over WebSocket).
///
/// Spawns the bin entrypoint, parses the bound port from stderr,
/// connects via a real WebSocket, and asserts the JSON-RPC handshake
/// works through the full HTTP+WS stack.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'acp --port 0 binds, accepts WS upgrade, handshakes',
    () async {
      final tmp = Directory.systemTemp.createTempSync('glue_serve_ws_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {
          // Windows can briefly hold a handle on the spawned server's
          // GLUE_HOME after kill; the OS reclaims the temp dir later.
        }
      });

      final process = await Process.start(
        'dart',
        ['run', '--verbosity=error', 'bin/glue.dart', 'acp', '--port', '0'],
        workingDirectory: _cliPackageRoot(),
        runInShell: true,
        environment: {
          'GLUE_HOME': tmp.path,
          'ANTHROPIC_API_KEY': 'sk-test-fake-for-validation',
        },
      );

      // Drain stderr; capture port from the [glue acp] banner.
      final portCompleter = Completer<int>();
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final match = RegExp(r'ws://[^:]+:(\d+)').firstMatch(line);
            if (match != null && !portCompleter.isCompleted) {
              portCompleter.complete(int.parse(match.group(1)!));
            }
          });
      addTearDown(() async {
        await stderrSub.cancel();
      });

      // Drain stdout (otherwise the OS pipe back-pressures).
      process.stdout.drain<void>().ignore();

      final port = await portCompleter.future.timeout(
        const Duration(seconds: 60),
      );

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/acp');

      // Buffer all inbound messages; match by id without broadcast-stream
      // subscription races.
      final received = <Map<String, Object?>>[];
      final pending = <int, Completer<Map<String, Object?>>>{};
      final wsSub = ws.listen((frame) {
        if (frame is! String) return;
        final msg = jsonDecode(frame) as Map<String, Object?>;
        received.add(msg);
        final id = msg['id'];
        if (id is int) {
          final c = pending.remove(id);
          c?.complete(msg);
        }
      });
      addTearDown(wsSub.cancel);

      Future<Map<String, Object?>> waitForId(int id) {
        final existing = received.where((message) => message['id'] == id);
        if (existing.isNotEmpty) {
          return Future.value(existing.first);
        }
        final completer = pending[id] = Completer<Map<String, Object?>>();
        return completer.future.timeout(const Duration(seconds: 30));
      }

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        }),
      );
      final initResp = await waitForId(1);
      final initResult = initResp['result']! as Map<Object?, Object?>;
      final agent = initResult['agentInfo']! as Map<Object?, Object?>;
      expect(agent['name'], 'glue');
      final capabilities =
          initResult['agentCapabilities']! as Map<Object?, Object?>;
      final sessionCapabilities =
          capabilities['sessionCapabilities']! as Map<Object?, Object?>;
      expect(sessionCapabilities['close'], <String, Object?>{});
      final authMethods = initResult['authMethods']! as List<Object?>;
      expect(authMethods, isNotEmpty);

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'session/new',
          'params': {'cwd': '/tmp/x'},
        }),
      );
      final newResp = await waitForId(2);
      final sessionId = (newResp['result']! as Map)['sessionId']! as String;
      expect(sessionId, startsWith('glue-'));

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'session/close',
          'params': {'sessionId': sessionId},
        }),
      );
      final closeResp = await waitForId(3);
      expect(closeResp['result'], <String, Object?>{});

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'session/prompt',
          'params': {
            'sessionId': sessionId,
            'prompt': [
              {'type': 'text', 'text': 'hi'},
            ],
          },
        }),
      );
      final errResp = await waitForId(4);
      expect((errResp['error']! as Map)['code'], -32001);

      await ws.close();
      process.kill(ProcessSignal.sigint);
      await process.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

String _cliPackageRoot() {
  final cwd = Directory.current.path;
  if (File('$cwd/bin/glue.dart').existsSync()) return cwd;
  if (File('$cwd/cli/bin/glue.dart').existsSync()) return '$cwd/cli';
  throw StateError('Could not locate cli/bin/glue.dart from $cwd');
}
