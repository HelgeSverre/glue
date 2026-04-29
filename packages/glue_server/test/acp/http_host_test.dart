import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_server/glue_server.dart';
import 'package:test/test.dart';

class _TextOnlyDelegate extends AcpServerDelegate {
  _TextOnlyDelegate();
  int sessionCounter = 0;

  @override
  Future<String> createSession(SessionNewParams params) async {
    sessionCounter++;
    return 'sess-$sessionCounter';
  }

  @override
  Stream<AgentEvent> prompt({
    required String sessionId,
    required String userMessage,
    required Future<bool> Function(ToolCall call) requestPermission,
  }) async* {
    // No scripted events — these tests focus on connection lifecycle.
  }

  @override
  void cancelPrompt(String sessionId) {}

  @override
  Future<void> closeSession(String sessionId) async {}
}

void main() {
  group('AcpHttpHost', () {
    test('one client: full initialize + session/new round-trip', () async {
      final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/acp');
      addTearDown(ws.close);

      final inbound = ws.asBroadcastStream();

      ws.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': 1},
      }));
      final initResp = await inbound.first as String;
      final initJson = jsonDecode(initResp) as Map<String, Object?>;
      expect(initJson['id'], 1);
      expect(
        ((initJson['result']! as Map)['agentInfo']! as Map)['name'],
        'glue',
      );

      ws.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/new',
        'params': {'cwd': '/tmp/x'},
      }));
      final newResp = await inbound.first as String;
      final newJson = jsonDecode(newResp) as Map<String, Object?>;
      expect(
        (newJson['result']! as Map)['sessionId'],
        startsWith('sess-'),
      );
    });

    test('multiple clients: each connection has isolated session state',
        () async {
      // delegateFactory returns a fresh delegate per connection, so
      // each WS client's `sess-1` is unique to its connection.
      final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      Future<String> firstSessionId(WebSocket ws) async {
        final inbound = ws.asBroadcastStream();
        ws.add(jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'session/new',
          'params': {'cwd': '/tmp/x'},
        }));
        final resp = await inbound.first as String;
        final json = jsonDecode(resp) as Map<String, Object?>;
        return (json['result']! as Map)['sessionId']! as String;
      }

      final a = await WebSocket.connect('ws://127.0.0.1:$port/acp');
      addTearDown(a.close);
      final b = await WebSocket.connect('ws://127.0.0.1:$port/acp');
      addTearDown(b.close);

      final aId = await firstSessionId(a);
      final bId = await firstSessionId(b);

      // Both connections see their first session as "sess-1" — proving
      // the delegate per-connection has its own counter.
      expect(aId, 'sess-1');
      expect(bId, 'sess-1');
      expect(host.activeConnections, 2);
    });

    test('rejects requests on the wrong path with 404', () async {
      final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final client = HttpClient();
      addTearDown(client.close);
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/wrong'));
      final response = await request.close();
      expect(response.statusCode, 404);
      await response.drain<void>();
    });

    test('rejects non-WebSocket requests with 400 on the WS path', () async {
      final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final client = HttpClient();
      addTearDown(client.close);
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/acp'));
      final response = await request.close();
      expect(response.statusCode, 400);
      await response.drain<void>();
    });
  });
}
