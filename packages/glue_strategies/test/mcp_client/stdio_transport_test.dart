/// Exercises [McpStdioTransport] against a real subprocess.
///
/// The "server" is a tiny Dart script we write to a temp file and run via
/// `dart run`. This means tests depend on `dart` being on `PATH`, which
/// is true in dev and CI. We do not require Node or any MCP reference
/// server here — that's covered by the integration tests in B3.
library;

import 'dart:io';

import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/transport/stdio.dart';
import 'package:test/test.dart';

/// Source for the in-test MCP echo server. Implements just enough of the
/// MCP wire protocol to round-trip an `initialize` + `tools/list` +
/// `tools/call` cycle. Newline-delimited JSON-RPC on stdin/stdout.
const _serverSource = r'''
import 'dart:convert';
import 'dart:io';

void main() async {
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.isEmpty) continue;
    final msg = jsonDecode(line) as Map<String, dynamic>;
    final method = msg['method'] as String?;
    final id = msg['id'];
    if (id == null) continue; // notification — no reply
    Map<String, dynamic>? result;
    if (method == 'initialize') {
      result = {
        'protocolVersion': '2025-03-26',
        'serverInfo': {'name': 'echo', 'version': '0.0.1'},
        'capabilities': {'tools': {'listChanged': false}},
      };
    } else if (method == 'tools/list') {
      result = {
        'tools': [
          {
            'name': 'echo',
            'description': 'echoes the message argument',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'message': {'type': 'string'},
              },
              'required': ['message'],
            },
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
    final response = {
      'jsonrpc': '2.0',
      'id': id,
      if (result != null) 'result': result,
      if (result == null)
        'error': {'code': -32601, 'message': 'Method not found'},
    };
    stdout.writeln(jsonEncode(response));
  }
}
''';

void main() {
  late Directory tmpDir;
  late File serverScript;

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('mcp_stdio_test_');
    serverScript = File('${tmpDir.path}/echo_server.dart');
    serverScript.writeAsStringSync(_serverSource);
  });

  tearDownAll(() {
    tmpDir.deleteSync(recursive: true);
  });

  Future<void> withClient(
    Future<void> Function(McpClient client) body, {
    bool inheritFullEnv = false,
  }) async {
    final transport = await McpStdioTransport.spawn(
      command: Platform.executable, // path to the running `dart` binary
      args: ['run', serverScript.path],
      inheritFullEnv: inheritFullEnv,
    );
    final client = McpClient(transport: transport);
    try {
      await body(client);
    } finally {
      await client.close();
    }
  }

  test(
      'round-trips initialize + tools/list + tools/call against a real subprocess',
      () async {
    await withClient((client) async {
      final init = await client.initialize();
      expect(init.serverInfo.name, 'echo');
      expect(init.protocolVersion, '2025-03-26');

      final tools = await client.listTools();
      expect(tools, hasLength(1));
      expect(tools.first.name, 'echo');

      final result = await client.callTool('echo', {'message': 'hi there'});
      expect(result.isError, isFalse);
      expect(result.textPayload, 'echo: hi there');
    });
  });

  test('close() shuts the child process down', () async {
    final transport = await McpStdioTransport.spawn(
      command: Platform.executable,
      args: ['run', serverScript.path],
    );
    final exit = transport.exitCode;
    await transport.close();
    // Either the child exited cleanly (0) or was killed (negative on
    // POSIX). Both are acceptable — the assertion is that close()
    // doesn't hang.
    final code = await exit.timeout(const Duration(seconds: 5));
    expect(code, isA<int>());
  });

  test('buildMcpStdioEnv: forwards only the allowlist + extras', () {
    final scrubbed = buildMcpStdioEnv(
      const {
        'PATH': '/usr/bin',
        'HOME': '/home/user',
        'OPENAI_API_KEY': 'should-not-leak',
        'AWS_SECRET_ACCESS_KEY': 'should-not-leak',
        'CUSTOM_PRIVATE': 'should-not-leak',
        'TERM': 'xterm-256color',
      },
      const {'MCP_SERVER_FLAG': 'on'},
    );
    expect(scrubbed['PATH'], '/usr/bin');
    expect(scrubbed['HOME'], '/home/user');
    expect(scrubbed['TERM'], 'xterm-256color');
    expect(scrubbed['MCP_SERVER_FLAG'], 'on');
    expect(scrubbed.containsKey('OPENAI_API_KEY'), isFalse);
    expect(scrubbed.containsKey('AWS_SECRET_ACCESS_KEY'), isFalse);
    expect(scrubbed.containsKey('CUSTOM_PRIVATE'), isFalse);
  });

  test('buildMcpStdioEnv: extras win on conflict with the allowlist', () {
    final scrubbed = buildMcpStdioEnv(
      const {'PATH': '/usr/bin'},
      const {'PATH': '/sandbox/bin'},
    );
    expect(scrubbed['PATH'], '/sandbox/bin');
  });
}
