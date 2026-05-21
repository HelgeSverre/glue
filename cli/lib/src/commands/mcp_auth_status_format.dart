/// Formatter for `glue mcp auth status` — one row per configured server
/// showing what credentials are stored and whether they're complete.
library;

import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/terminal/tty_style.dart';

enum McpAuthState { stored, missing, notLoggedIn, none }

class McpAuthStatusRow {
  const McpAuthStatusRow({
    required this.id,
    required this.kind,
    required this.state,
  });
  final String id;

  /// Free-form auth kind label: 'bearer' | 'oauth' | 'none'.
  final String kind;
  final McpAuthState state;
}

String formatMcpAuthStatus(List<McpAuthStatusRow> rows, {bool? ansiEnabled}) {
  if (rows.isEmpty) return 'No MCP servers configured.';
  final ansi = ansiEnabled ?? stdoutSupportsAnsi();
  final idWidth = rows
      .map((r) => r.id.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final dot = ansi ? '$brandDot ' : '';
  return [
    '$dot${styledOrPlain('MCP credentials', (s) => s.bold, ansiEnabled: ansi)}',
    ...rows.map((r) => _formatRow(r, idWidth, ansi: ansi)),
  ].join('\n');
}

String _formatRow(McpAuthStatusRow r, int idWidth, {required bool ansi}) {
  final id = styledOrPlain(
    r.id.padRight(idWidth),
    (s) => s.bold,
    ansiEnabled: ansi,
  );
  final marker = ansi ? '${_markerFor(r.state)} ' : '';
  final tag = styledOrPlain(
    _tagFor(r),
    _tagStyleFor(r.state),
    ansiEnabled: ansi,
  );
  return '  $id  $marker$tag';
}

String _markerFor(McpAuthState s) {
  return switch (s) {
    McpAuthState.stored => markerOk,
    McpAuthState.missing => markerWarn,
    McpAuthState.notLoggedIn => markerWarn,
    McpAuthState.none => markerInfo,
  };
}

Styled Function(Styled) _tagStyleFor(McpAuthState s) {
  return switch (s) {
    McpAuthState.stored => (x) => x.green,
    McpAuthState.missing => (x) => x.yellow,
    McpAuthState.notLoggedIn => (x) => x.yellow,
    McpAuthState.none => (x) => x.gray,
  };
}

String _tagFor(McpAuthStatusRow r) {
  return switch (r.state) {
    McpAuthState.stored => '${r.kind} (stored)',
    McpAuthState.missing => '${r.kind} (missing)',
    McpAuthState.notLoggedIn => '${r.kind} (not logged in)',
    McpAuthState.none => 'none',
  };
}
