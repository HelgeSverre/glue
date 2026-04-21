import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/mcp/mcp_client.dart';
import 'package:glue/src/mcp/mcp_config.dart';
import 'package:glue/src/mcp/mcp_server_manager.dart';
import 'package:glue/src/mcp/mcp_tool_proxy.dart';
import 'package:glue/src/mcp/mcp_transport.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeTransport implements McpTransport {
  final List<String> called = [];
  Map<String, dynamic>? nextResult;
  Exception? nextError;

  @override
  Future<Map<String, dynamic>> request(
      String method, Map<String, dynamic>? params) async {
    called.add(method);
    if (nextError != null) throw nextError!;
    return nextResult ?? {};
  }

  @override
  Future<void> notify(String method, Map<String, dynamic>? params) async {
    called.add('notify:$method');
  }

  @override
  Stream<McpNotification> get notifications => const Stream.empty();

  @override
  Future<void> close() async {}
}

// ---------------------------------------------------------------------------
// McpClient tests
// ---------------------------------------------------------------------------

void main() {
  group('McpClient', () {
    test('initialize sends initialize request and notifications/initialized',
        () async {
      final transport = _FakeTransport()
        ..nextResult = {
          'protocolVersion': '2025-03-26',
          'capabilities': {
            'tools': {'listChanged': true},
          },
          'serverInfo': {'name': 'test-server', 'version': '1.0'},
        };
      final client = McpClient(transport);

      await client.initialize();

      expect(transport.called, contains('initialize'));
      expect(transport.called, contains('notify:notifications/initialized'));
      expect(client.serverName, 'test-server');
      expect(client.serverVersion, '1.0');
      expect(client.capabilities?.hasTools, isTrue);
      expect(client.capabilities?.toolListChangedSupported, isTrue);
    });

    test('listTools returns parsed tool definitions', () async {
      final transport = _FakeTransport()
        ..nextResult = {
          'tools': [
            {
              'name': 'read_file',
              'description': 'Read a file',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string', 'description': 'File path'},
                },
                'required': ['path'],
              },
            },
          ],
        };
      final client = McpClient(transport);

      final tools = await client.listTools();

      expect(tools, hasLength(1));
      expect(tools[0].name, 'read_file');
      expect(tools[0].description, 'Read a file');
      expect(tools[0].inputSchema, isNotEmpty);
    });

    test('listTools returns empty list when tools field is missing', () async {
      final transport = _FakeTransport()..nextResult = {};
      final client = McpClient(transport);

      final tools = await client.listTools();
      expect(tools, isEmpty);
    });

    test('callTool returns McpToolResult with text content', () async {
      final transport = _FakeTransport()
        ..nextResult = {
          'content': [
            {'type': 'text', 'text': 'file contents here'},
          ],
          'isError': false,
        };
      final client = McpClient(transport);

      final result = await client.callTool('read_file', {'path': '/tmp/test'});

      expect(result.isError, isFalse);
      expect(result.textContent, 'file contents here');
      expect(result.content, hasLength(1));
    });

    test('callTool returns error result when isError is true', () async {
      final transport = _FakeTransport()
        ..nextResult = {
          'content': [
            {'type': 'text', 'text': 'File not found'},
          ],
          'isError': true,
        };
      final client = McpClient(transport);

      final result = await client.callTool('read_file', {'path': '/bad'});

      expect(result.isError, isTrue);
      expect(result.textContent, 'File not found');
    });
  });

  // ---------------------------------------------------------------------------
  // McpToolProxy tests
  // ---------------------------------------------------------------------------

  group('McpToolProxy', () {
    _FakeTransport makeTransport(Map<String, dynamic> result) =>
        _FakeTransport()..nextResult = result;

    test('name is namespaced as serverId__toolName', () {
      final proxy = McpToolProxy(
        serverId: 'myserver',
        def: const McpToolDef(
            name: 'read_file', description: 'read', inputSchema: {}),
        client: McpClient(_FakeTransport()),
      );
      expect(proxy.name, 'myserver__read_file');
    });

    test('description falls back to server name when absent', () {
      final proxy = McpToolProxy(
        serverId: 'srv',
        def: const McpToolDef(name: 'tool', inputSchema: {}),
        client: McpClient(_FakeTransport()),
      );
      expect(proxy.description, contains('srv'));
    });

    test('trust is ToolTrust.command', () {
      final proxy = McpToolProxy(
        serverId: 's',
        def: const McpToolDef(name: 't', inputSchema: {}),
        client: McpClient(_FakeTransport()),
      );
      expect(proxy.trust, ToolTrust.command);
    });

    test('parameters are extracted from JSON schema', () {
      const schema = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'path': <String, dynamic>{
            'type': 'string',
            'description': 'File path',
          },
          'encoding': <String, dynamic>{
            'type': 'string',
            'description': 'Encoding',
          },
        },
        'required': ['path'],
      };
      final proxy = McpToolProxy(
        serverId: 's',
        def: const McpToolDef(name: 't', inputSchema: schema),
        client: McpClient(_FakeTransport()),
      );

      expect(proxy.parameters, hasLength(2));
      final pathParam = proxy.parameters.firstWhere((p) => p.name == 'path');
      expect(pathParam.required, isTrue);
      expect(pathParam.type, 'string');

      final encParam = proxy.parameters.firstWhere((p) => p.name == 'encoding');
      expect(encParam.required, isFalse);
    });

    test('execute returns success ToolResult on successful call', () async {
      final transport = makeTransport({
        'content': [
          {'type': 'text', 'text': 'hello world'},
        ],
        'isError': false,
      });

      final proxy = McpToolProxy(
        serverId: 'srv',
        def: const McpToolDef(name: 'tool', inputSchema: {}),
        client: McpClient(transport),
      );

      final result = await proxy.execute({'arg': 'value'});
      expect(result.success, isTrue);
      expect(result.content, contains('hello world'));
      expect(result.metadata['mcp_server'], 'srv');
      expect(result.metadata['mcp_tool'], 'tool');
    });

    test('execute returns failure ToolResult on error response', () async {
      final transport = makeTransport({
        'content': [
          {'type': 'text', 'text': 'Something went wrong'},
        ],
        'isError': true,
      });

      final proxy = McpToolProxy(
        serverId: 'srv',
        def: const McpToolDef(name: 'tool', inputSchema: {}),
        client: McpClient(transport),
      );

      final result = await proxy.execute({});
      expect(result.success, isFalse);
    });

    test('execute handles transport exception gracefully', () async {
      final transport = _FakeTransport()
        ..nextError = Exception('connection lost');

      final proxy = McpToolProxy(
        serverId: 'srv',
        def: const McpToolDef(name: 'tool', inputSchema: {}),
        client: McpClient(transport),
      );

      final result = await proxy.execute({});
      expect(result.success, isFalse);
      expect(result.content, contains('connection lost'));
    });
  });

  // ---------------------------------------------------------------------------
  // McpServerManager tests
  // ---------------------------------------------------------------------------

  group('McpServerManager', () {
    test('loadConfig registers enabled servers', () {
      final tools = <String, Tool>{};
      final manager = McpServerManager(agentTools: tools);

      manager.loadConfig(const McpConfig(servers: {
        'srv': McpServerConfig(
          id: 'srv',
          name: 'Server',
          transport: McpStdioConfig(command: 'cmd'),
        ),
      }));

      expect(manager.servers, contains('srv'));
      expect(manager.servers['srv']!.status, McpServerStatus.disconnected);
    });

    test('loadConfig skips disabled servers', () {
      final tools = <String, Tool>{};
      final manager = McpServerManager(agentTools: tools);

      manager.loadConfig(const McpConfig(servers: {
        'disabled': McpServerConfig(
          id: 'disabled',
          name: 'Disabled Server',
          transport: McpStdioConfig(command: 'cmd'),
          enabled: false,
        ),
      }));

      expect(manager.servers, isEmpty);
    });

    test('servers returns unmodifiable view', () {
      final tools = <String, Tool>{};
      final manager = McpServerManager(agentTools: tools);
      manager.loadConfig(const McpConfig());

      // Should not be the same instance as the internal map.
      // Verify unmodifiability by checking the runtime type.
      final servers = manager.servers;
      expect(servers, isA<Map<String, McpServerState>>());
      // Map.unmodifiable wraps with an unmodifiable view — verify via exception.
      expect(
        () => servers.remove('nonexistent'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('disposeAll completes without errors on empty config', () async {
      final tools = <String, Tool>{};
      final manager = McpServerManager(agentTools: tools);
      manager.loadConfig(const McpConfig());
      await expectLater(manager.disposeAll(), completes);
    });

    test('connect throws on unknown server id', () async {
      final manager = McpServerManager(agentTools: {});
      manager.loadConfig(const McpConfig());
      await expectLater(
        () => manager.connect('nonexistent'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // McpToolResult / McpContent tests
  // ---------------------------------------------------------------------------

  group('McpToolResult', () {
    test('textContent joins multiple text parts', () {
      const result = McpToolResult(
        content: [
          McpContent(type: 'text', text: 'part1'),
          McpContent(type: 'text', text: 'part2'),
        ],
      );
      expect(result.textContent, 'part1\npart2');
    });

    test('textContent ignores non-text content', () {
      const result = McpToolResult(
        content: [
          McpContent(type: 'image', data: 'base64data'),
          McpContent(type: 'text', text: 'caption'),
        ],
      );
      expect(result.textContent, 'caption');
    });

    test('textContent returns empty string when no text parts', () {
      const result = McpToolResult(
        content: [McpContent(type: 'image', data: 'd')],
      );
      expect(result.textContent, isEmpty);
    });

    test('fromJson parses isError', () {
      final result = McpToolResult.fromJson({
        'content': [
          {'type': 'text', 'text': 'err'},
        ],
        'isError': true,
      });
      expect(result.isError, isTrue);
    });
  });
}
