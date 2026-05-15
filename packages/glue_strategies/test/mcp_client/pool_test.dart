import 'dart:io';

import 'package:glue_server/glue_server.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

import 'in_memory_transport.dart';

/// Fake factory that hands back an [McpClient] backed by an
/// [InMemoryMcpTransport] pre-loaded with canned responses for
/// `initialize` and `tools/list`.
McpClientFactory _fakeFactory({
  required Map<String, List<McpToolDescriptor>> toolsByServer,
}) {
  return (spec, credentials) async {
    final tools = toolsByServer[spec.id] ?? const <McpToolDescriptor>[];
    final transport = InMemoryMcpTransport(respond: (out) async {
      if (out is! JsonRpcRequest) return [];
      switch (out.method) {
        case McpMethod.initialize:
          return [
            JsonRpcResponse(id: out.id, result: {
              'protocolVersion': mcpProtocolVersion,
              'serverInfo': {'name': 'fake-${spec.id}', 'version': '1.0'},
              'capabilities': {
                'tools': {'listChanged': true},
              },
            }),
          ];
        case McpMethod.toolsList:
          return [
            JsonRpcResponse(id: out.id, result: {
              'tools': tools.map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'inputSchema': t.inputSchema,
                  }).toList(),
            }),
          ];
        default:
          return [];
      }
    });
    return McpClient(transport: transport);
  };
}

/// Factory that always throws on `initialize` — used to test the
/// "server fails to start" path.
McpClientFactory _failingFactory() {
  return (spec, credentials) async =>
      throw const McpCallFailure(
        reason: 'spawn_failed',
        message: 'cannot spawn',
      );
}

CredentialStore _emptyCreds() => CredentialStore(
      path: '${Directory.systemTemp.createTempSync('pool_test_').path}/creds.json',
      env: const {},
    );

void main() {
  group('McpClientPool — connect lifecycle', () {
    test('connectAll: each server connects + advertises tools', () async {
      const fsServer = McpStdioServerSpec(
        id: 'fs',
        command: 'fake',
      );
      const dbServer = McpStdioServerSpec(
        id: 'db',
        command: 'fake',
      );
      final pool = McpClientPool(
        config: const McpConfig(servers: [fsServer, dbServer]),
        credentials: _emptyCreds(),
        clientFactory: _fakeFactory(toolsByServer: const {
          'fs': [
            McpToolDescriptor(
              name: 'read_file',
              description: '',
              inputSchema: {'type': 'object'},
            ),
          ],
          'db': [
            McpToolDescriptor(
              name: 'query',
              description: '',
              inputSchema: {'type': 'object'},
            ),
          ],
        }),
      );

      final captured = <McpPoolEvent>[];
      final sub = pool.events.listen(captured.add);

      pool.connectAll();
      // Allow microtasks + transport responses to settle.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(pool.unhealthyCount, 0);
      expect(pool.allTools.map((t) => t.name).toSet(), {
        'fs-read_file',
        'db-query',
      });
      expect(
        captured.whereType<McpPoolServerConnectedEvent>().length,
        2,
      );
      await sub.cancel();
      await pool.close();
    });

    test('disabled servers are skipped at connect time', () async {
      const disabled = McpStdioServerSpec(
        id: 'parked',
        command: 'fake',
        enabled: false,
      );
      final pool = McpClientPool(
        config: const McpConfig(servers: [disabled]),
        credentials: _emptyCreds(),
        clientFactory: _fakeFactory(toolsByServer: const {}),
      );
      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pool.server('parked')?.state, isA<McpDisconnected>());
      expect(pool.allTools, isEmpty);
      await pool.close();
    });

    test('failing server transitions to dead + emits error event', () async {
      const failer = McpStdioServerSpec(
        id: 'broken',
        command: 'fake',
      );
      final pool = McpClientPool(
        config: const McpConfig(servers: [failer]),
        credentials: _emptyCreds(),
        clientFactory: _failingFactory(),
      );

      final captured = <McpPoolEvent>[];
      final sub = pool.events.listen(captured.add);

      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(pool.server('broken')?.state, isA<McpDead>());
      expect(captured.whereType<McpPoolServerErrorEvent>(), isNotEmpty);
      expect(pool.unhealthyCount, 1);

      await sub.cancel();
      await pool.close();
    });

    test('one server failing does not kill the others', () async {
      const ok = McpStdioServerSpec(id: 'ok', command: 'fake');

      // Mixed factory: 'ok' succeeds, 'bad' throws.
      Future<McpClient> mixed(McpServerSpec spec, CredentialStore creds) {
        if (spec.id == 'bad') {
          throw const McpCallFailure(reason: 'spawn_failed');
        }
        return _fakeFactory(toolsByServer: const {
          'ok': [
            McpToolDescriptor(
              name: 'works',
              description: '',
              inputSchema: {'type': 'object'},
            ),
          ],
        })(spec, creds);
      }

      final pool = McpClientPool(
        config: const McpConfig(servers: [
          ok,
          McpStdioServerSpec(id: 'bad', command: 'fake'),
        ]),
        credentials: _emptyCreds(),
        clientFactory: mixed,
      );

      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(pool.allTools.map((t) => t.name), ['ok-works']);
      expect(pool.unhealthyCount, 1);

      await pool.close();
    });
  });

  group('McpClientPool — reservedToolNames', () {
    test('native names win — MCP descriptor with same name is dropped',
        () async {
      const spec = McpStdioServerSpec(id: 'fs', command: 'fake');
      final pool = McpClientPool(
        config: const McpConfig(servers: [spec]),
        credentials: _emptyCreds(),
        reservedToolNames: const {'read_file'},
        clientFactory: _fakeFactory(toolsByServer: const {
          'fs': [
            McpToolDescriptor(
              name: 'read_file',
              description: '',
              inputSchema: {'type': 'object'},
            ),
            McpToolDescriptor(
              name: 'list_directory',
              description: '',
              inputSchema: {'type': 'object'},
            ),
          ],
        }),
      );

      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // read_file was reserved; list_directory makes it through namespaced.
      expect(pool.allTools.map((t) => t.name), ['fs-list_directory']);
      await pool.close();
    });
  });

  group('McpClientPool — toggle / reconnect', () {
    test('toggle disables a connected server and removes its tools',
        () async {
      const spec = McpStdioServerSpec(id: 'fs', command: 'fake');
      final pool = McpClientPool(
        config: const McpConfig(servers: [spec]),
        credentials: _emptyCreds(),
        clientFactory: _fakeFactory(toolsByServer: const {
          'fs': [
            McpToolDescriptor(
              name: 'read_file',
              description: '',
              inputSchema: {'type': 'object'},
            ),
          ],
        }),
      );

      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pool.allTools, hasLength(1));

      await pool.toggle('fs');
      expect(pool.allTools, isEmpty);
      expect(pool.server('fs')!.enabled, isFalse);

      await pool.close();
    });
  });
}
