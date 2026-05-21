import 'package:glue/src/commands/mcp_list_format.dart';
import 'package:test/test.dart';

void main() {
  group('formatMcpServerList', () {
    test('empty → "No MCP servers configured" + config path hint', () {
      final result = formatMcpServerList(
        const [],
        configPath: '/home/test/.glue/config.yaml',
      );
      expect(result, contains('No MCP servers configured'));
      expect(result, contains('/home/test/.glue/config.yaml'));
      expect(result, contains('mcp.servers'));
    });

    test('rows list id, transport, and enabled state in input order', () {
      final result = formatMcpServerList(const [
        McpServerListRow(id: 'fs', kind: 'stdio', enabled: true),
        McpServerListRow(id: 'parked', kind: 'http+sse', enabled: false),
      ], configPath: '/x.yaml');
      expect(result, contains('fs'));
      expect(result, contains('parked'));
      expect(result, contains('stdio'));
      expect(result, contains('http+sse'));
      // Ordering matters — `fs` before `parked`.
      expect(result.indexOf('fs'), lessThan(result.indexOf('parked')));
      // Default off (no TTY in dart test) → no ANSI.
      expect(result, isNot(contains('\x1b[')));
    });

    test('hint to use `/mcp` shows up at the end', () {
      final result = formatMcpServerList(const [
        McpServerListRow(id: 'fs', kind: 'stdio', enabled: true),
      ], configPath: '/x.yaml');
      expect(result, contains('/mcp'));
    });

    group('with ANSI enabled', () {
      test('header is prefixed with the brand dot', () {
        final result = formatMcpServerList(
          const [McpServerListRow(id: 'fs', kind: 'stdio', enabled: true)],
          configPath: '/x.yaml',
          ansiEnabled: true,
        );
        expect(result, contains('●'));
        expect(result, contains('\x1b['));
      });

      test('enabled rows use the OK marker (✓); disabled use info (·)', () {
        final result = formatMcpServerList(
          const [
            McpServerListRow(id: 'on', kind: 'stdio', enabled: true),
            McpServerListRow(id: 'off', kind: 'stdio', enabled: false),
          ],
          configPath: '/x.yaml',
          ansiEnabled: true,
        );
        final onLine = result
            .split('\n')
            .firstWhere((line) => line.contains('on '));
        final offLine = result
            .split('\n')
            .firstWhere((line) => line.contains('off'));
        expect(onLine, contains('✓'));
        expect(offLine, contains('·'));
      });
    });
  });
}
