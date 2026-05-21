/// Formatter for `glue mcp list` — shape mirrors `mcp_tools_format.dart`.
/// Takes a list of simple value rows so the command stays thin and the
/// output is unit-testable without a real config.
library;

import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';

class McpServerListRow {
  const McpServerListRow({
    required this.id,
    required this.kind,
    required this.enabled,
  });
  final String id;
  final String kind;
  final bool enabled;
}

String formatMcpServerList(
  List<McpServerListRow> rows, {
  required String configPath,
  bool? ansiEnabled,
}) {
  final ansi = ansiEnabled ?? stdoutSupportsAnsi();

  if (rows.isEmpty) {
    return [
      'No MCP servers configured.',
      'Add a server under `mcp.servers:` in $configPath.',
    ].join('\n');
  }

  final idWidth = rows
      .map((r) => r.id.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final kindWidth = rows
      .map((r) => r.kind.length)
      .fold<int>(0, (a, b) => a > b ? a : b);

  final dot = ansi ? '$brandDot ' : '';
  final header =
      '$dot${styledOrPlain('MCP servers', (s) => s.bold, ansiEnabled: ansi)}';

  return [
    header,
    ...rows.map((r) => _formatRow(r, idWidth, kindWidth, ansi: ansi)),
    '',
    styledOrPlain(
      'Use `/mcp` inside a Glue session for live connection state.',
      (s) => s.gray,
      ansiEnabled: ansi,
    ),
  ].join('\n');
}

String _formatRow(
  McpServerListRow r,
  int idWidth,
  int kindWidth, {
  required bool ansi,
}) {
  final id = styledOrPlain(
    r.id.padRight(idWidth),
    (s) => s.bold,
    ansiEnabled: ansi,
  );
  final kind = styledOrPlain(
    r.kind.padRight(kindWidth),
    (s) => s.gray,
    ansiEnabled: ansi,
  );
  final stateWord = r.enabled ? 'enabled' : 'disabled';
  final styledState = styledOrPlain(
    stateWord,
    r.enabled ? (s) => s.green : (s) => s.gray,
    ansiEnabled: ansi,
  );
  final marker = ansi ? '${r.enabled ? markerOk : markerInfo} ' : '';
  return '  $id  $kind  $marker$styledState';
}
