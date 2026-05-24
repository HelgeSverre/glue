import 'package:glue/src/commands/slash/mcp.dart' show resolveMcpAuthActions;
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('resolveMcpAuthActions', () {
    final remoteSpec = McpUrlServerSpec(
      id: 'foo',
      url: Uri.parse('https://foo.example/mcp'),
      isWebSocket: false,
      auth: const McpOAuthAuth(),
    );
    const stdioSpec = McpStdioServerSpec(id: 'bar', command: 'echo');

    test('stdio servers never get auth actions', () {
      final actions = resolveMcpAuthActions(
        spec: stdioSpec,
        state: const McpDisconnected(),
        hasAccessToken: false,
      );
      expect(actions, isEmpty);
    });

    test('AwaitingAuth shows Authenticate', () {
      final actions = resolveMcpAuthActions(
        spec: remoteSpec,
        state: const McpAwaitingAuth(),
        hasAccessToken: false,
      );
      expect(actions, ['Authenticate']);
    });

    test('Disconnected without token shows Authenticate', () {
      final actions = resolveMcpAuthActions(
        spec: remoteSpec,
        state: const McpDisconnected(),
        hasAccessToken: false,
      );
      expect(actions, ['Authenticate']);
    });

    test('Connected + access token shows Re-authenticate + Sign out', () {
      final actions = resolveMcpAuthActions(
        spec: remoteSpec,
        state: McpConnected(
          connectedAt: DateTime.now(),
          serverName: 'X',
          serverVersion: '1',
          protocolVersion: '2025-03-26',
        ),
        hasAccessToken: true,
      );
      expect(actions, ['Re-authenticate', 'Sign out']);
    });
  });
}
