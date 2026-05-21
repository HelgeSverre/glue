import 'package:glue_server/glue_server.dart';
import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:glue_strategies/src/mcp_client/transport/http_sse.dart';
import 'package:test/test.dart';

import 'in_memory_transport.dart';

JsonRpcResponse _ok(Object id, Map<String, dynamic> result) =>
    JsonRpcResponse(id: id, result: result);

JsonRpcError _err(Object id, int code, String message) =>
    JsonRpcError(id: id, code: code, message: message);

void main() {
  group('McpClient.initialize', () {
    test(
      'happy path negotiates protocol version and returns server info',
      () async {
        final transport = InMemoryMcpTransport(
          respond: (out) async {
            if (out is JsonRpcRequest && out.method == McpMethod.initialize) {
              return [
                _ok(out.id, {
                  'protocolVersion': mcpProtocolVersion,
                  'serverInfo': {'name': 'fake-server', 'version': '1.0.0'},
                  'capabilities': {
                    'tools': {'listChanged': true},
                  },
                }),
              ];
            }
            return [];
          },
        );
        final client = McpClient(transport: transport);

        final result = await client.initialize();
        expect(result.protocolVersion, mcpProtocolVersion);
        expect(result.serverInfo.name, 'fake-server');
        expect(result.capabilities.tools?.listChanged, isTrue);

        // We should have sent: initialize request, then initialized notification.
        expect(transport.outgoing.length, 2);
        expect(transport.outgoing[0], isA<JsonRpcRequest>());
        expect(
          (transport.outgoing[0] as JsonRpcRequest).method,
          McpMethod.initialize,
        );
        expect(transport.outgoing[1], isA<JsonRpcNotification>());
        expect(
          (transport.outgoing[1] as JsonRpcNotification).method,
          McpMethod.initialized,
        );

        await client.close();
      },
    );

    test(
      'refuses protocol versions below the minimum-supported floor',
      () async {
        final transport = InMemoryMcpTransport(
          respond: (out) async {
            if (out is JsonRpcRequest && out.method == McpMethod.initialize) {
              return [
                _ok(out.id, {
                  'protocolVersion': '2024-01-01', // way below minimum
                  'serverInfo': {'name': 'ancient', 'version': '0.1'},
                  'capabilities': const {},
                }),
              ];
            }
            return [];
          },
        );
        final client = McpClient(transport: transport);

        await expectLater(
          client.initialize(),
          throwsA(
            isA<McpCallFailure>().having(
              (e) => e.reason,
              'reason',
              'protocol_too_old',
            ),
          ),
        );
        await client.close();
      },
    );
  });

  group('McpClient.listTools', () {
    test('returns parsed descriptors', () async {
      final transport = InMemoryMcpTransport(
        respond: (out) async {
          if (out is JsonRpcRequest && out.method == McpMethod.toolsList) {
            return [
              _ok(out.id, {
                'tools': [
                  {
                    'name': 'echo',
                    'description': 'echoes its input',
                    'inputSchema': {
                      'type': 'object',
                      'properties': {
                        'message': {'type': 'string'},
                      },
                    },
                  },
                  {
                    'name': 'add',
                    'description': 'adds two numbers',
                    'inputSchema': {'type': 'object'},
                  },
                ],
              }),
            ];
          }
          return [];
        },
      );
      final client = McpClient(transport: transport);

      final tools = await client.listTools();
      expect(tools, hasLength(2));
      expect(tools[0].name, 'echo');
      expect(tools[0].description, 'echoes its input');
      expect(tools[1].name, 'add');
      await client.close();
    });
  });

  group('McpClient.callTool', () {
    test('returns text content concatenated as textPayload', () async {
      final transport = InMemoryMcpTransport(
        respond: (out) async {
          if (out is JsonRpcRequest && out.method == McpMethod.toolsCall) {
            return [
              _ok(out.id, {
                'content': [
                  {'type': 'text', 'text': 'line 1'},
                  {'type': 'text', 'text': 'line 2'},
                ],
              }),
            ];
          }
          return [];
        },
      );
      final client = McpClient(transport: transport);

      final result = await client.callTool('echo', {'msg': 'hi'});
      expect(result.isError, isFalse);
      expect(result.textPayload, 'line 1\nline 2');
      await client.close();
    });

    test('surfaces server error as McpCallFailure with code', () async {
      final transport = InMemoryMcpTransport(
        respond: (out) async {
          if (out is JsonRpcRequest && out.method == McpMethod.toolsCall) {
            return [_err(out.id, -32602, 'invalid args')];
          }
          return [];
        },
      );
      final client = McpClient(transport: transport);

      await expectLater(
        client.callTool('bad', const {}),
        throwsA(
          isA<McpCallFailure>()
              .having((e) => e.code, 'code', -32602)
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
      await client.close();
    });

    test('retries once on rate-limit error then succeeds', () async {
      var attempts = 0;
      final transport = InMemoryMcpTransport(
        respond: (out) async {
          if (out is JsonRpcRequest && out.method == McpMethod.toolsCall) {
            attempts++;
            if (attempts == 1) {
              return [_err(out.id, McpErrorCode.rateLimited, 'slow down')];
            }
            return [
              _ok(out.id, {
                'content': [
                  {'type': 'text', 'text': 'done'},
                ],
              }),
            ];
          }
          return [];
        },
      );
      final client = McpClient(transport: transport);

      final result = await client.callTool('slow', const {});
      expect(result.textPayload, 'done');
      expect(attempts, 2);
      await client.close();
    });
  });

  group('McpClient drop handling', () {
    test(
      'pending callTool resolves with retryable failure on transport drop',
      () async {
        // Transport that never responds — we hold the request open and
        // then simulate a drop.
        final transport = InMemoryMcpTransport(respond: (_) async => []);
        final client = McpClient(transport: transport);

        final futureFailure = client.callTool('hang', const {});
        // Let the request flush to the transport.
        await Future<void>.delayed(Duration.zero);
        transport.simulateDrop();

        await expectLater(
          futureFailure,
          throwsA(
            isA<McpCallFailure>()
                .having((e) => e.reason, 'reason', 'disconnected')
                .having((e) => e.retryable, 'retryable', isTrue),
          ),
        );
        await client.close();
      },
    );
  });

  group('McpClient auth handling', () {
    test('401 from transport surfaces as auth_expired retryable failure',
        () async {
      final transport = InMemoryMcpTransport();
      final client = McpClient(transport: transport);
      final pending = client.callTool('foo', {});
      transport.pushError(
        const McpHttpTransportError(
          statusCode: 401,
          body: '',
          wwwAuthenticate:
              'Bearer resource_metadata="https://example/.well-known/oauth-protected-resource"',
        ),
      );
      final err = await pending.then<McpCallFailure?>(
        (_) => null,
        onError: (Object e) => e as McpCallFailure,
      );
      expect(err, isNotNull);
      expect(err!.reason, 'auth_expired');
      expect(err.retryable, isTrue);
      expect(
        err.wwwAuthenticate,
        'Bearer resource_metadata="https://example/.well-known/oauth-protected-resource"',
      );
      await client.close();
    });
  });

  group('McpClient notifications', () {
    test('surfaces server-side notifications on the stream', () async {
      final transport = InMemoryMcpTransport();
      final client = McpClient(transport: transport);

      final captured = <McpNotification>[];
      final sub = client.notifications.listen(captured.add);

      transport.pushFromServer(
        const JsonRpcNotification(method: McpMethod.toolsListChanged),
      );
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      expect(captured.first.method, McpMethod.toolsListChanged);

      await sub.cancel();
      await client.close();
    });
  });

  group('McpClient timeout', () {
    test(
      'times out a request after callTimeout with retryable failure',
      () async {
        // Transport that never responds.
        final transport = InMemoryMcpTransport(respond: (_) async => []);
        final client = McpClient(
          transport: transport,
          callTimeout: const Duration(milliseconds: 50),
        );

        await expectLater(
          client.callTool('hang', const {}),
          throwsA(
            isA<McpCallFailure>()
                .having((e) => e.reason, 'reason', 'timeout')
                .having((e) => e.retryable, 'retryable', isTrue),
          ),
        );
        await client.close();
      },
    );
  });
}
