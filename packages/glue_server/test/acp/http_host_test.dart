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
    List<ContentPart> userContentParts = const [],
  }) async* {
    // No scripted events — these tests focus on connection lifecycle.
  }

  @override
  void cancelPrompt(String sessionId) {}

  @override
  UsageReport usageSummary(String sessionId) =>
      buildUsageReport(usageEvents: const [], sessionId: sessionId);

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

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        }),
      );
      final initResp = await inbound.first as String;
      final initJson = jsonDecode(initResp) as Map<String, Object?>;
      expect(initJson['id'], 1);
      expect(
        ((initJson['result']! as Map)['agentInfo']! as Map)['name'],
        'glue',
      );

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'session/new',
          'params': {'cwd': '/tmp/x'},
        }),
      );
      final newResp = await inbound.first as String;
      final newJson = jsonDecode(newResp) as Map<String, Object?>;
      expect((newJson['result']! as Map)['sessionId'], startsWith('sess-'));
    });

    test(
      'multiple clients: each connection has isolated session state',
      () async {
        // delegateFactory returns a fresh delegate per connection, so
        // each WS client's `sess-1` is unique to its connection.
        final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
        final port = await host.start(port: 0);
        addTearDown(host.stop);

        Future<String> firstSessionId(WebSocket ws) async {
          final inbound = ws.asBroadcastStream();
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'session/new',
              'params': {'cwd': '/tmp/x'},
            }),
          );
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
      },
    );

    test('rejects requests on the wrong path with 404', () async {
      final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/wrong'),
      );
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
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/acp'),
      );
      final response = await request.close();
      expect(response.statusCode, 400);
      await response.drain<void>();
    });
  });

  group('AcpHttpHost bearer token', () {
    test('rejects connections without a token header or query', () async {
      final host = AcpHttpHost(
        delegateFactory: _TextOnlyDelegate.new,
        bearerToken: 'secret-abc',
      );
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/acp'),
      );
      final response = await request.close();
      expect(response.statusCode, 401);
      expect(
        response.headers.value(HttpHeaders.wwwAuthenticateHeader),
        contains('Bearer'),
      );
      await response.drain<void>();
    });

    test('rejects WS upgrades with a wrong token', () async {
      final host = AcpHttpHost(
        delegateFactory: _TextOnlyDelegate.new,
        bearerToken: 'secret-abc',
      );
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:$port/acp',
          headers: const {'Authorization': 'Bearer wrong'},
        ),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('accepts WS upgrades with the correct Authorization header', () async {
      final host = AcpHttpHost(
        delegateFactory: _TextOnlyDelegate.new,
        bearerToken: 'secret-abc',
      );
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final ws = await WebSocket.connect(
        'ws://127.0.0.1:$port/acp',
        headers: const {'Authorization': 'Bearer secret-abc'},
      );
      addTearDown(ws.close);

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        }),
      );
      final reply = await ws.first as String;
      expect((jsonDecode(reply) as Map)['id'], 1);
    });

    test('accepts WS upgrades with the correct ?token= query param', () async {
      final host = AcpHttpHost(
        delegateFactory: _TextOnlyDelegate.new,
        bearerToken: 'secret-abc',
      );
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final ws = await WebSocket.connect(
        'ws://127.0.0.1:$port/acp?token=secret-abc',
      );
      addTearDown(ws.close);

      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        }),
      );
      final reply = await ws.first as String;
      expect((jsonDecode(reply) as Map)['id'], 1);
    });
  });

  group('AcpHttpHost Origin defense (H7)', () {
    test(
      'rejects an upgrade request carrying an Origin header with 403',
      () async {
        // A browser attaches `Origin` to every WebSocket handshake; native /
        // editor ACP clients do not. Rejecting any request that carries an
        // Origin header defeats the DNS-rebinding / drive-by attack where a
        // visited website opens ws://127.0.0.1:<port>/acp to drive the agent.
        final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
        final port = await host.start(port: 0);
        addTearDown(host.stop);

        final client = HttpClient();
        addTearDown(client.close);
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/acp'),
        );
        request.headers.add('origin', 'http://evil.example');
        final response = await request.close();
        expect(response.statusCode, 403);
        await response.drain<void>();
      },
    );

    test('still accepts an upgrade request without an Origin header', () async {
      final host = AcpHttpHost(delegateFactory: _TextOnlyDelegate.new);
      final port = await host.start(port: 0);
      addTearDown(host.stop);

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/acp');
      addTearDown(ws.close);
      ws.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': 1},
        }),
      );
      final reply = await ws.first as String;
      expect((jsonDecode(reply) as Map)['id'], 1);
    });
  });

  group('AcpHttpHost connection resilience (H10)', () {
    test(
      'a throwing delegateFactory neither crashes the host nor stops accepting',
      () async {
        // The first connection's delegateFactory throws inside
        // _runConnection, which is dispatched un-awaited. Without a catch
        // this is an isolate-fatal unhandled async error; with one, the host
        // logs, tears down that socket, and keeps accepting.
        var attempts = 0;
        final host = AcpHttpHost(
          delegateFactory: () {
            attempts++;
            if (attempts == 1) {
              throw StateError('delegate init boom');
            }
            return _TextOnlyDelegate();
          },
        );
        final port = await host.start(port: 0);
        addTearDown(host.stop);

        // First connection: upgrade succeeds, then the factory throws.
        final doomed = await WebSocket.connect('ws://127.0.0.1:$port/acp');
        addTearDown(doomed.close);
        // Give _runConnection time to run and (pre-fix) surface the uncaught
        // error into the test zone.
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Second connection must still handshake — proof the host survived.
        final ws = await WebSocket.connect('ws://127.0.0.1:$port/acp');
        addTearDown(ws.close);
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {'protocolVersion': 1},
          }),
        );
        final reply = await ws.cast<String>().first.timeout(
          const Duration(seconds: 5),
        );
        expect((jsonDecode(reply) as Map)['id'], 1);
      },
    );
  });
}
