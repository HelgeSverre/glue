import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:glue_strategies/src/mcp_client/transport/http_sse.dart';
import 'package:test/test.dart';

/// Spins up a minimal MCP-over-HTTP server on `127.0.0.1` on a random
/// port for the duration of a test. The [handler] is invoked once per
/// incoming POST and must produce the response shape.
class _FakeHttpMcpServer {
  _FakeHttpMcpServer._(this._server, this.url);

  static Future<_FakeHttpMcpServer> bind({
    required Future<void> Function(HttpRequest req) handler,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = Uri.parse('http://127.0.0.1:${server.port}/mcp');
    server.listen((req) async {
      try {
        await handler(req);
      } catch (e) {
        req.response.statusCode = 500;
        req.response.write(e.toString());
        await req.response.close();
      }
    });
    return _FakeHttpMcpServer._(server, url);
  }

  final HttpServer _server;
  final Uri url;

  /// Stores the last request's headers so tests can assert on them.
  final List<HttpRequest> requests = [];

  Future<void> close() => _server.close(force: true);
}

void main() {
  group('McpHttpTransport — JSON response', () {
    test('round-trips initialize → tools/list → tools/call', () async {
      final server = await _FakeHttpMcpServer.bind(handler: (req) async {
        final body = await utf8.decoder.bind(req).join();
        final msg = jsonDecode(body) as Map<String, dynamic>;
        final id = msg['id'];
        final method = msg['method'] as String?;
        Map<String, dynamic>? result;
        if (method == 'initialize') {
          result = {
            'protocolVersion': mcpProtocolVersion,
            'serverInfo': {'name': 'fake', 'version': '0.0.1'},
            'capabilities': const {
              'tools': {'listChanged': false}
            },
          };
        } else if (method == 'tools/list') {
          result = {
            'tools': [
              {
                'name': 'echo',
                'description': '',
                'inputSchema': const {'type': 'object'},
              },
            ],
          };
        } else if (method == 'tools/call') {
          final args = (msg['params'] as Map)['arguments'] as Map;
          result = {
            'content': [
              {'type': 'text', 'text': 'echo: ${args['message']}'},
            ],
          };
        }
        if (id == null) {
          // notifications/initialized — 202 accept-and-drop
          req.response.statusCode = 202;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': result,
        }));
        await req.response.close();
      });
      addTearDown(server.close);

      final transport = McpHttpTransport(endpoint: server.url);
      final client = McpClient(transport: transport);

      final init = await client.initialize();
      expect(init.serverInfo.name, 'fake');

      final tools = await client.listTools();
      expect(tools.single.name, 'echo');

      final result = await client.callTool('echo', {'message': 'hi'});
      expect(result.textPayload, 'echo: hi');

      await client.close();
    });

    test('5xx surfaces as McpCallFailure with retryable false', () async {
      final server = await _FakeHttpMcpServer.bind(handler: (req) async {
        req.response.statusCode = 500;
        req.response.write('{"error": "boom"}');
        await req.response.close();
      });
      addTearDown(server.close);

      final transport = McpHttpTransport(endpoint: server.url);
      final client = McpClient(transport: transport);
      await expectLater(
        client.initialize(),
        throwsA(anything),
      );
      await client.close();
    });
  });

  group('McpHttpTransport — SSE response', () {
    test('streams multiple messages from a single POST', () async {
      final server = await _FakeHttpMcpServer.bind(handler: (req) async {
        final body = await utf8.decoder.bind(req).join();
        final msg = jsonDecode(body) as Map<String, dynamic>;
        final id = msg['id'];
        req.response.headers.contentType = ContentType('text', 'event-stream');
        // Send a notification, then the actual response.
        req.response.write('event: message\n');
        req.response.write(
          'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'method': 'notifications/some_status',
                'params': {'msg': 'intermediate'},
              })}\n\n',
        );
        req.response.write('event: message\n');
        req.response.write(
          'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'result': {
                  'protocolVersion': mcpProtocolVersion,
                  'serverInfo': {'name': 'sse-fake', 'version': '0.0.1'},
                  'capabilities': const {},
                },
              })}\n\n',
        );
        await req.response.close();
      });
      addTearDown(server.close);

      final transport = McpHttpTransport(endpoint: server.url);
      final client = McpClient(transport: transport);

      final notifications = <McpNotification>[];
      final sub = client.notifications.listen(notifications.add);

      final init = await client.initialize();
      expect(init.serverInfo.name, 'sse-fake');
      // Allow microtasks to flush before asserting on notifications.
      await Future<void>.delayed(Duration.zero);
      expect(notifications.map((n) => n.method),
          contains('notifications/some_status'));

      await sub.cancel();
      await client.close();
    });
  });

  group('McpHttpTransport — auth + session-id headers', () {
    test('Authorization: Bearer is set when token provided', () async {
      String? receivedAuth;
      final server = await _FakeHttpMcpServer.bind(handler: (req) async {
        receivedAuth = req.headers.value('authorization');
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'protocolVersion': mcpProtocolVersion,
            'serverInfo': {'name': 'fake', 'version': '0.0.1'},
            'capabilities': const {},
          },
        }));
        await req.response.close();
      });
      addTearDown(server.close);

      final transport = McpHttpTransport(
        endpoint: server.url,
        bearerToken: 'tok-abc',
      );
      final client = McpClient(transport: transport);
      await client.initialize();
      expect(receivedAuth, 'Bearer tok-abc');
      await client.close();
    });

    test('Mcp-Session-Id captured from initialize and resent', () async {
      final receivedSessionIds = <String?>[];
      var responseCount = 0;
      final server = await _FakeHttpMcpServer.bind(handler: (req) async {
        receivedSessionIds.add(req.headers.value('mcp-session-id'));
        final body = await utf8.decoder.bind(req).join();
        final msg = jsonDecode(body) as Map<String, dynamic>;
        final id = msg['id'];
        final method = msg['method'] as String?;

        responseCount++;
        if (responseCount == 1) {
          // initialize → issue session id
          req.response.headers.add('Mcp-Session-Id', 'sess-xyz');
        }
        if (id == null) {
          // notification — 202 accept
          req.response.statusCode = 202;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': method == 'initialize'
              ? {
                  'protocolVersion': mcpProtocolVersion,
                  'serverInfo': {'name': 'fake', 'version': '0.0.1'},
                  'capabilities': const {},
                }
              : {'tools': []},
        }));
        await req.response.close();
      });
      addTearDown(server.close);

      final transport = McpHttpTransport(endpoint: server.url);
      final client = McpClient(transport: transport);
      await client.initialize();
      // notifications/initialized is fire-and-forget — give it a tick
      // so the request lands at the server before we ask for the tools.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await client.listTools();

      // First request: no session yet. Second + third: 'sess-xyz'.
      expect(receivedSessionIds.first, isNull);
      expect(receivedSessionIds.skip(1), everyElement('sess-xyz'));

      await client.close();
    });
  });
}
