import 'package:glue_server/glue_server.dart';
import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:glue_strategies/src/mcp_client/tool_factory.dart';
import 'package:test/test.dart';

import 'in_memory_transport.dart';

McpClient _client(InMemoryMcpTransport transport) =>
    McpClient(transport: transport);

void main() {
  group('McpTool.execute', () {
    test('returns success with concatenated text payload', () async {
      final transport = InMemoryMcpTransport(
        respond: (out) async {
          if (out is JsonRpcRequest && out.method == McpMethod.toolsCall) {
            return [
              JsonRpcResponse(
                id: out.id,
                result: {
                  'content': [
                    {'type': 'text', 'text': 'echo: hi'},
                  ],
                },
              ),
            ];
          }
          return [];
        },
      );
      final client = _client(transport);
      final tool = McpTool(
        client: client,
        serverId: 'fake',
        bareName: 'echo',
        descriptor: const McpToolDescriptor(
          name: 'echo',
          description: 'echoes input',
          inputSchema: {'type': 'object'},
        ),
      );

      final result = await tool.execute({'message': 'hi'});
      expect(result.success, isTrue);
      expect(result.content, 'echo: hi');
      expect(result.metadata['mcp.server_id'], 'fake');
      expect(result.metadata['mcp.tool'], 'echo');
      await client.close();
    });

    test('disconnected client → retryable failure', () async {
      final transport = InMemoryMcpTransport(respond: (_) async => []);
      final client = _client(transport);
      final tool = McpTool(
        client: client,
        serverId: 'fake',
        bareName: 'hang',
        descriptor: const McpToolDescriptor(
          name: 'hang',
          description: '',
          inputSchema: {'type': 'object'},
        ),
      );

      final fut = tool.execute(const {});
      await Future<void>.delayed(Duration.zero);
      transport.simulateDrop();

      final result = await fut;
      expect(result.success, isFalse);
      expect(result.metadata['retryable'], isTrue);
      expect(result.metadata['mcp.failure_reason'], 'disconnected');
      await client.close();
    });

    test('server isError=true surfaces success=false', () async {
      final transport = InMemoryMcpTransport(
        respond: (out) async {
          if (out is JsonRpcRequest && out.method == McpMethod.toolsCall) {
            return [
              JsonRpcResponse(
                id: out.id,
                result: {
                  'isError': true,
                  'content': [
                    {'type': 'text', 'text': 'tool said no'},
                  ],
                },
              ),
            ];
          }
          return [];
        },
      );
      final client = _client(transport);
      final tool = McpTool(
        client: client,
        serverId: 'fake',
        bareName: 'bad',
        descriptor: const McpToolDescriptor(
          name: 'bad',
          description: '',
          inputSchema: {'type': 'object'},
        ),
      );

      final result = await tool.execute(const {});
      expect(result.success, isFalse);
      expect(result.content, 'tool said no');
      expect(result.metadata['mcp.is_error'], isTrue);
      await client.close();
    });
  });

  group('buildMcpTools', () {
    test('namespaces every tool with the server id', () {
      final transport = InMemoryMcpTransport();
      final client = _client(transport);
      final tools = buildMcpTools(
        client: client,
        serverId: 'fs',
        descriptors: const [
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
      );
      expect(tools.map((t) => t.name), ['fs__read_file', 'fs__list_directory']);
      client.close();
    });

    test('reservedNames filters out conflicting descriptors', () {
      final transport = InMemoryMcpTransport();
      final client = _client(transport);
      final tools = buildMcpTools(
        client: client,
        serverId: 'fs',
        descriptors: const [
          McpToolDescriptor(
            name: 'read_file',
            description: '',
            inputSchema: {},
          ),
          McpToolDescriptor(
            name: 'unique_tool',
            description: '',
            inputSchema: {},
          ),
        ],
        reservedNames: {'read_file'},
      );
      expect(tools.map((t) => t.bareName), ['unique_tool']);
      client.close();
    });
  });

  group('inputSchema → ToolParameter', () {
    test('extracts properties + required + types', () {
      final transport = InMemoryMcpTransport();
      final client = _client(transport);
      final tool = McpTool(
        client: client,
        serverId: 's',
        bareName: 't',
        descriptor: const McpToolDescriptor(
          name: 't',
          description: '',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'file path'},
              'limit': {'type': 'integer'},
            },
            'required': ['path'],
          },
        ),
      );
      final params = tool.parameters;
      expect(params.map((p) => p.name).toSet(), {'path', 'limit'});
      final path = params.firstWhere((p) => p.name == 'path');
      expect(path.required, isTrue);
      expect(path.type, 'string');
      expect(path.description, 'file path');
      final limit = params.firstWhere((p) => p.name == 'limit');
      expect(limit.required, isFalse);
      expect(limit.type, 'integer');
      client.close();
    });

    test('schema with no properties returns empty parameter list', () {
      final transport = InMemoryMcpTransport();
      final client = _client(transport);
      final tool = McpTool(
        client: client,
        serverId: 's',
        bareName: 't',
        descriptor: const McpToolDescriptor(
          name: 't',
          description: '',
          inputSchema: {'type': 'object'},
        ),
      );
      expect(tool.parameters, isEmpty);
      client.close();
    });
  });
}
