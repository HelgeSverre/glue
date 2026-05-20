/// Shared formatter for `glue mcp tools` (CLI) and `/mcp tools` (slash):
/// renders a grouped, human-readable listing of tools by MCP server.
///
/// Pure: takes simple value objects so it's unit-testable without spinning
/// up a real `McpClientPool`.
library;

import 'package:glue_strategies/glue_strategies.dart';

enum McpServerListingStatus {
  connected,
  connecting,
  reconnecting,
  disconnected,
  dead,
  disabled,
}

class McpToolEntry {
  const McpToolEntry({required this.name, this.description = ''});
  final String name;
  final String description;
}

class McpServerToolListing {
  const McpServerToolListing({
    required this.id,
    required this.status,
    this.tools = const [],
    this.error,
  });
  final String id;
  final McpServerListingStatus status;
  final List<McpToolEntry> tools;
  final String? error;
}

String formatMcpToolsByServer(Iterable<McpServerToolListing> servers) {
  if (servers.isEmpty) {
    return 'No MCP servers configured.';
  }
  return servers.map(_formatServer).join('\n\n');
}

String _formatServer(McpServerToolListing server) {
  final header = '${server.id}${_annotation(server)}:';
  if (server.tools.isEmpty) {
    return '$header\n  ${_emptyReason(server)}';
  }
  return [
    header,
    ...server.tools.map(
      (t) => t.description.isEmpty
          ? '  ${t.name}'
          : '  ${t.name} — ${t.description}',
    ),
  ].join('\n');
}

String _annotation(McpServerToolListing server) {
  return switch (server.status) {
    McpServerListingStatus.connected => '',
    McpServerListingStatus.connecting => ' (connecting)',
    McpServerListingStatus.reconnecting => ' (reconnecting)',
    McpServerListingStatus.disconnected => ' (not connected)',
    McpServerListingStatus.dead => ' (dead)',
    McpServerListingStatus.disabled => ' (disabled)',
  };
}

/// Project an [McpServerSnapshot] into the simple value object the
/// formatter takes. Keeps the pool's runtime types out of the formatter.
McpServerToolListing listingFromSnapshot(McpServerSnapshot s) {
  return McpServerToolListing(
    id: s.id,
    status: _statusOf(s),
    tools: s.tools
        .map((t) => McpToolEntry(name: t.bareName, description: t.description))
        .toList(),
    error: s.lastError,
  );
}

McpServerListingStatus _statusOf(McpServerSnapshot s) {
  if (!s.enabled) return McpServerListingStatus.disabled;
  return switch (s.state) {
    McpConnected() => McpServerListingStatus.connected,
    McpConnecting() => McpServerListingStatus.connecting,
    McpReconnecting() => McpServerListingStatus.reconnecting,
    McpDead() => McpServerListingStatus.dead,
    McpDisconnected() => McpServerListingStatus.disconnected,
  };
}

String _emptyReason(McpServerToolListing server) {
  final error = server.error;
  return switch (server.status) {
    McpServerListingStatus.connected => 'no tools advertised',
    McpServerListingStatus.connecting => 'still connecting; tools unknown',
    McpServerListingStatus.reconnecting => 'reconnecting; tools unknown',
    McpServerListingStatus.disconnected => 'not connected; tools unknown',
    McpServerListingStatus.dead =>
      error == null ? 'dead; tools unknown' : 'dead: $error',
    McpServerListingStatus.disabled => 'disabled; enable to list tools',
  };
}
