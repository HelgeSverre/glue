import 'package:glue/src/commands/mcp_tools_format.dart';
import 'package:glue/src/terminal/brand.dart';
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

    group('with ANSI enabled', () {
      test('server header is prefixed with the brand dot', () {
        final result = formatMcpToolsByServer(const [
          McpServerToolListing(
            id: 'fs',
            status: McpServerListingStatus.connected,
            tools: [McpToolEntry(name: 'read')],
          ),
        ], ansiEnabled: true);
        expect(result, contains('●'));
        expect(result.indexOf('●'), lessThan(result.indexOf('fs')),
            reason: 'brand dot must precede the id');
        expect(result, contains('\x1b['),
            reason: 'expected ANSI sequences when ansiEnabled: true');
      });

      test('dead server\'s empty-reason line uses the error marker (✗)', () {
        final result = formatMcpToolsByServer(const [
          McpServerToolListing(
            id: 'broken',
            status: McpServerListingStatus.dead,
            error: 'handshake timeout',
          ),
        ], ansiEnabled: true);
        // The error marker glyph plus the error text both appear.
        expect(result, contains('✗'));
        expect(result, contains('handshake timeout'));
      });

      test('disabled server uses the info marker (·)', () {
        final result = formatMcpToolsByServer(const [
          McpServerToolListing(
            id: 'parked',
            status: McpServerListingStatus.disabled,
          ),
        ], ansiEnabled: true);
        expect(result, contains('·'));
        expect(result, contains('disabled'));
      });

      test('disconnected/connecting/reconnecting use the warn marker (!)', () {
        for (final s in [
          McpServerListingStatus.disconnected,
          McpServerListingStatus.connecting,
          McpServerListingStatus.reconnecting,
        ]) {
          final result = formatMcpToolsByServer([
            McpServerToolListing(id: 'fs', status: s),
          ], ansiEnabled: true);
          expect(result, contains('!'), reason: 'status $s should warn');
        }
      });
    });

    test('default (ansiEnabled omitted, no TTY in dart test) stays plain', () {
      // Sanity: in the dart-test runner there is no TTY, so by default the
      // formatter must not emit ANSI sequences.
      final result = formatMcpToolsByServer(const [
        McpServerToolListing(
          id: 'fs',
          status: McpServerListingStatus.connected,
          tools: [McpToolEntry(name: 'read')],
        ),
      ]);
      expect(result, isNot(contains('\x1b[')));
      // brandDot itself is plain '●' when ANSI is off; we don't *forbid* it
      // appearing, but the previous default output didn't include it.
      expect(result, isNot(startsWith(brandDot)));
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
