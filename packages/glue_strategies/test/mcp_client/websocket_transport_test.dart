import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:glue_strategies/src/mcp_client/transport/websocket.dart';
import 'package:test/test.dart';

/// Minimal MCP-over-WebSocket test server. Each text frame is a single
/// JSON-RPC message; the handler echoes responses for `initialize` and
/// `tools/list` synchronously.
class _FakeWsMcpServer {
  _FakeWsMcpServer._(this._server, this.url);

  static Future<_FakeWsMcpServer> bind({String? requiredBearer}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = Uri.parse('ws://127.0.0.1:${server.port}/mcp');
    server.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        if (requiredBearer != null) {
          final auth = req.headers.value('authorization');
          if (auth != 'Bearer $requiredBearer') {
            req.response.statusCode = 401;
            await req.response.close();
            return;
          }
        }
        // Server-side socket lifetime ends when the test tears down
        // the parent HttpServer.
        // ignore: close_sinks
        final socket = await WebSocketTransformer.upgrade(req);
        socket.listen((frame) {
          final msg = jsonDecode(frame as String) as Map<String, dynamic>;
          final id = msg['id'];
          final method = msg['method'] as String?;
          if (id == null) return; // notification
          Map<String, dynamic>? result;
          if (method == 'initialize') {
            result = {
              'protocolVersion': mcpProtocolVersion,
              'serverInfo': {'name': 'ws-fake', 'version': '0.0.1'},
              'capabilities': const {},
            };
          } else if (method == 'tools/list') {
            result = {'tools': const []};
          }
          socket.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': result ?? const {},
          }));
        });
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _FakeWsMcpServer._(server, url);
  }

  final HttpServer _server;
  final Uri url;

  Future<void> close() => _server.close(force: true);
}

void main() {
  group('connectMcpWebSocket', () {
    test('rejects non-ws/wss URLs synchronously', () async {
      await expectLater(
        connectMcpWebSocket(url: Uri.parse('http://example.com/x')),
        throwsArgumentError,
      );
    });

    test('round-trips initialize + tools/list', () async {
      final server = await _FakeWsMcpServer.bind();
      addTearDown(server.close);

      final transport = await connectMcpWebSocket(url: server.url);
      final client = McpClient(transport: transport);
      final init = await client.initialize();
      expect(init.serverInfo.name, 'ws-fake');
      final tools = await client.listTools();
      expect(tools, isEmpty);
      await client.close();
    });

    test('forwards bearer token via Authorization header', () async {
      final server = await _FakeWsMcpServer.bind(requiredBearer: 'tok-xyz');
      addTearDown(server.close);

      final transport = await connectMcpWebSocket(
        url: server.url,
        bearerToken: 'tok-xyz',
      );
      final client = McpClient(transport: transport);
      final init = await client.initialize();
      expect(init.serverInfo.name, 'ws-fake');
      await client.close();
    });

    test('rejects connection when bearer is missing', () async {
      final server = await _FakeWsMcpServer.bind(requiredBearer: 'tok-xyz');
      addTearDown(server.close);

      await expectLater(
        connectMcpWebSocket(url: server.url),
        throwsA(isA<McpWebSocketConnectError>()),
      );
    });
  });
}
