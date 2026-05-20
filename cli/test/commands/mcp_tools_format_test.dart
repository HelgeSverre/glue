import 'package:glue/src/commands/mcp_tools_format.dart';
import 'package:test/test.dart';

void main() {
  group('formatMcpToolsByServer', () {
    test('empty input → "No MCP servers configured" message', () {
      final result = formatMcpToolsByServer(const []);
      expect(result, contains('No MCP servers configured'));
    });

    test('connected server with tools → header + indented tool lines', () {
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'fs',
          status: McpServerListingStatus.connected,
          tools: [
            McpToolEntry(name: 'read', description: 'Read a file'),
            McpToolEntry(name: 'write'),
          ],
        ),
      ]);
      final lines = result.split('\n');
      expect(lines.first, contains('fs'));
      expect(result, contains('  read — Read a file'));
      expect(result, contains('  write'));
      // The bare 'write' line shouldn't have an em-dash since no description.
      expect(result, isNot(contains('write —')));
    });

    test('disabled server → annotated, no tools section', () {
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'parked',
          status: McpServerListingStatus.disabled,
        ),
      ]);
      expect(result, contains('parked'));
      expect(result, contains('disabled'));
    });

    test('disconnected server with no tools → status annotation', () {
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'fs',
          status: McpServerListingStatus.disconnected,
        ),
      ]);
      expect(result, contains('fs'));
      expect(result, contains('not connected'));
    });

    test('dead server → surfaces error reason', () {
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'broken',
          status: McpServerListingStatus.dead,
          error: 'handshake timeout',
        ),
      ]);
      expect(result, contains('broken'));
      expect(result, contains('handshake timeout'));
    });

    test('connected server with zero tools → notes the empty advertisement',
        () {
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'empty',
          status: McpServerListingStatus.connected,
        ),
      ]);
      expect(result, contains('empty'));
      expect(result, contains('no tools'));
    });

    test('two connected servers → two grouped blocks in input order', () {
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'fs',
          status: McpServerListingStatus.connected,
          tools: [McpToolEntry(name: 'read')],
        ),
        McpServerToolListing(
          id: 'db',
          status: McpServerListingStatus.connected,
          tools: [McpToolEntry(name: 'query')],
        ),
      ]);
      final fsIndex = result.indexOf('fs');
      final dbIndex = result.indexOf('db');
      expect(fsIndex, greaterThanOrEqualTo(0));
      expect(dbIndex, greaterThan(fsIndex),
          reason: 'groups should appear in input order');
      expect(result, contains('  read'));
      expect(result, contains('  query'));
    });
  });
}
