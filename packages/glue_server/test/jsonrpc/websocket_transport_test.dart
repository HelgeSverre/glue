import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_server/glue_server.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketTransport', () {
    test('round-trips JSON-RPC messages through a real WS connection',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      // Server side: echo every inbound JSON-RPC request back as a response.
      final acceptedTransport = _serverTransport(server);

      final client = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
      addTearDown(client.close);
      final clientTransport = WebSocketTransport(client);

      // Wire server: echo
      unawaited(acceptedTransport.then((t) {
        t.incoming.listen((msg) {
          if (msg is JsonRpcRequest) {
            t.send(JsonRpcResponse(id: msg.id, result: 'echo:${msg.method}'));
          }
        });
      }));

      clientTransport.send(const JsonRpcRequest(id: 1, method: 'ping'));
      final reply = await clientTransport.incoming
          .firstWhere((m) => m is JsonRpcResponse);
      expect(reply, isA<JsonRpcResponse>());
      expect((reply as JsonRpcResponse).result, 'echo:ping');

      await clientTransport.close();
    });

    test('decodes inbound binary frames as UTF-8 JSON', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final received = <JsonRpcMessage>[];
      unawaited(_serverTransport(server).then((t) {
        t.incoming.listen(received.add);
      }));

      final client = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
      // Send the JSON as a binary frame (List<int>) — the transport
      // should still decode it.
      client.add(utf8.encode(
        '{"jsonrpc":"2.0","id":7,"method":"binary"}',
      ));
      // Tiny delay for delivery.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await client.close();

      expect(received, hasLength(1));
      expect(received.single, isA<JsonRpcRequest>());
      expect((received.single as JsonRpcRequest).method, 'binary');
    });
  });
}

// ignore_for_file: close_sinks
// This file owns several WebSocket sinks; their lifetimes are governed
// by the returned WebSocketTransport's close() (driven by addTearDown
// in the tests above) or by the test's process-exit teardown. The
// analyzer's flow-sensitive lint can't see across the future
// boundaries, so we suppress per-file rather than line-by-line.

/// Accepts the next WebSocket upgrade on [server] and returns its
/// [WebSocketTransport].
Future<WebSocketTransport> _serverTransport(HttpServer server) async {
  final request = await server.first;
  final socket = await WebSocketTransformer.upgrade(request);
  return WebSocketTransport(socket);
}
