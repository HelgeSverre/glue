/// Shared formatter for `glue mcp tools` (CLI) and `/mcp tools` (slash):
/// renders a grouped, human-readable listing of tools by MCP server.
///
/// Pure: takes simple value objects so it's unit-testable without spinning
/// up a real `McpClientPool`.
library;

import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/tty_style.dart';

enum McpServerListingStatus {
  connected,
  connecting,
  reconnecting,
  disconnected,
  needsAuth,
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

String formatMcpToolsByServer(
  Iterable<McpServerToolListing> servers, {
  bool? ansiEnabled,
}) {
  final ansi = ansiEnabled ?? stdoutSupportsAnsi();
  if (servers.isEmpty) {
    return 'No MCP servers configured.';
  }
  return servers.map((s) => _formatServer(s, ansi: ansi)).join('\n\n');
}

String _formatServer(McpServerToolListing server, {required bool ansi}) {
  final dot = ansi ? '$brandDot ' : '';
  final id = styledOrPlain(server.id, (s) => s.bold, ansiEnabled: ansi);
  final annotation = _annotation(server, ansi: ansi);
  final header = '$dot$id$annotation:';
  if (server.tools.isEmpty) {
    final reason = _emptyReasonLine(server, ansi: ansi);
    return '$header\n  $reason';
  }
  return [
    header,
    ...server.tools.map((t) => _formatTool(t, ansi: ansi)),
  ].join('\n');
}

String _formatTool(McpToolEntry t, {required bool ansi}) {
  final name = styledOrPlain(t.name, (s) => s.bold, ansiEnabled: ansi);
  if (t.description.isEmpty) return '  $name';
  final dash = styledOrPlain('—', (s) => s.gray, ansiEnabled: ansi);
  final desc = styledOrPlain(t.description, (s) => s.gray, ansiEnabled: ansi);
  return '  $name $dash $desc';
}

String _annotation(McpServerToolListing server, {required bool ansi}) {
  final raw = switch (server.status) {
    McpServerListingStatus.connected => '',
    McpServerListingStatus.connecting => ' (connecting)',
    McpServerListingStatus.reconnecting => ' (reconnecting)',
    McpServerListingStatus.disconnected => ' (not connected)',
    McpServerListingStatus.needsAuth => ' (needs auth)',
    McpServerListingStatus.dead => ' (dead)',
    McpServerListingStatus.disabled => ' (disabled)',
  };
  if (raw.isEmpty) return '';
  return ' ${styledOrPlain(raw.trimLeft(), _annotationStyle(server.status), ansiEnabled: ansi)}';
}

Styled Function(Styled) _annotationStyle(McpServerListingStatus s) =>
    switch (s) {
      McpServerListingStatus.connected => (x) => x,
      McpServerListingStatus.connecting => (x) => x.yellow,
      McpServerListingStatus.reconnecting => (x) => x.yellow,
      McpServerListingStatus.disconnected => (x) => x.yellow,
      McpServerListingStatus.needsAuth => (x) => x.yellow,
      McpServerListingStatus.dead => (x) => x.red,
      McpServerListingStatus.disabled => (x) => x.gray,
    };

String _emptyReasonLine(McpServerToolListing server, {required bool ansi}) {
  final reason = _emptyReasonText(server);
  if (!ansi) return reason;
  final marker = switch (server.status) {
    McpServerListingStatus.connected => markerInfo,
    McpServerListingStatus.connecting => markerWarn,
    McpServerListingStatus.reconnecting => markerWarn,
    McpServerListingStatus.disconnected => markerWarn,
    McpServerListingStatus.needsAuth => markerWarn,
    McpServerListingStatus.dead => markerError,
    McpServerListingStatus.disabled => markerInfo,
  };
  return '$marker ${styledOrPlain(reason, (s) => s.gray, ansiEnabled: ansi)}';
}

String _emptyReasonText(McpServerToolListing server) {
  final error = server.error;
  return switch (server.status) {
    McpServerListingStatus.connected => 'no tools advertised',
    McpServerListingStatus.connecting => 'still connecting; tools unknown',
    McpServerListingStatus.reconnecting => 'reconnecting; tools unknown',
    McpServerListingStatus.disconnected => 'not connected; tools unknown',
    McpServerListingStatus.needsAuth =>
      error == null
          ? 'needs auth; run `/mcp auth login`'
          : 'needs auth: $error',
    McpServerListingStatus.dead =>
      error == null ? 'dead; tools unknown' : 'dead: $error',
    McpServerListingStatus.disabled => 'disabled; enable to list tools',
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
    McpAwaitingAuth() => McpServerListingStatus.needsAuth,
  };
}
