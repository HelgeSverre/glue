import 'package:glue/src/commands/mcp_auth_status_format.dart';
import 'package:test/test.dart';

void main() {
  group('formatMcpAuthStatus', () {
    test('empty → "No MCP servers configured."', () {
      expect(
          formatMcpAuthStatus(const []), contains('No MCP servers configured'));
    });

    test('each row prints id + auth kind + state tag', () {
      final result = formatMcpAuthStatus(const [
        McpAuthStatusRow(
            id: 'github', kind: 'bearer', state: McpAuthState.stored),
        McpAuthStatusRow(
            id: 'api', kind: 'bearer', state: McpAuthState.missing),
        McpAuthStatusRow(
            id: 'saas', kind: 'oauth', state: McpAuthState.notLoggedIn),
        McpAuthStatusRow(id: 'fs', kind: 'none', state: McpAuthState.none),
      ]);
      expect(result, contains('github'));
      expect(result, contains('bearer'));
      expect(result, contains('stored'));
      expect(result, contains('api'));
      expect(result, contains('missing'));
      expect(result, contains('saas'));
      expect(result, contains('not logged in'));
      expect(result, contains('fs'));
      expect(result, contains('none'));
    });

    test('default (no TTY) emits no ANSI', () {
      final result = formatMcpAuthStatus(const [
        McpAuthStatusRow(
            id: 'github', kind: 'bearer', state: McpAuthState.stored),
      ]);
      expect(result, isNot(contains('\x1b[')));
    });

    group('with ANSI enabled', () {
      test('stored uses ✓, missing/not-logged-in use !, none uses ·', () {
        final result = formatMcpAuthStatus(const [
          McpAuthStatusRow(
              id: 'stored', kind: 'bearer', state: McpAuthState.stored),
          McpAuthStatusRow(
              id: 'gone', kind: 'bearer', state: McpAuthState.missing),
          McpAuthStatusRow(
              id: 'fresh', kind: 'oauth', state: McpAuthState.notLoggedIn),
          McpAuthStatusRow(id: 'open', kind: 'none', state: McpAuthState.none),
        ], ansiEnabled: true);
        final lines = result.split('\n');
        expect(lines.firstWhere((l) => l.contains('stored')), contains('✓'));
        expect(lines.firstWhere((l) => l.contains('gone')), contains('!'));
        expect(lines.firstWhere((l) => l.contains('fresh')), contains('!'));
        expect(lines.firstWhere((l) => l.contains('open')), contains('·'));
      });
    });
  });
}
