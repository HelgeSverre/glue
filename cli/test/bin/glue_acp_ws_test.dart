/// End-to-end tests for `glue serve --port N` (ACP over WebSocket).
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
  test('serve --port 0 binds, accepts WS upgrade, handshakes', () async {
    final tmp = Directory.systemTemp.createTempSync('glue_serve_ws_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final process = await Process.start(
      'dart',
      ['run', 'bin/glue.dart', 'serve', '--port', '0'],
      workingDirectory: Directory.current.path,
      runInShell: true,
      environment: {
        'GLUE_HOME': tmp.path,
        'ANTHROPIC_API_KEY': 'sk-test-fake-for-validation',
      },
    );

    // Drain stderr; capture port from the [glue serve] banner.
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

    final port =
        await portCompleter.future.timeout(const Duration(seconds: 60));

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
      final existing =
          received.where((m) => m['id'] == id).cast<Map<String, Object?>?>();
      if (existing.isNotEmpty) return Future.value(existing.first);
      final c = pending[id] = Completer<Map<String, Object?>>();
      return c.future.timeout(const Duration(seconds: 30));
    }

    ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': 1},
    }));
    final initResp = await waitForId(1);
    final agent =
        (initResp['result']! as Map)['agentInfo'] as Map<Object?, Object?>;
    expect(agent['name'], 'glue');

    ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'session/new',
      'params': {'cwd': '/tmp/x'},
    }));
    final newResp = await waitForId(2);
    expect((newResp['result']! as Map)['sessionId'], startsWith('glue-'));

    await ws.close();
    process.kill(ProcessSignal.sigint);
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }, timeout: const Timeout(Duration(seconds: 120)));
}
