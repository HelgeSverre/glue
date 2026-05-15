import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';
import 'package:glue/src/terminal/styled.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';

/// `/mcp` — inspect MCP server state inside a running Glue session.
///
/// Forms:
///   • `/mcp`        → opens a status panel (visual table)
///   • `/mcp list`   → prints a text table inline (greppable)
///
/// Action sub-commands (toggle, reconnect, call, auth) land in B7.
class McpSlashCommand extends SlashCommand {
  McpSlashCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'mcp';

  @override
  String get description => 'Inspect MCP servers';

  @override
  String execute(List<String> args) {
    if (args.isEmpty) {
      _openPanel();
      return '';
    }
    if (args.first == 'list') return _textList();
    return 'Unknown /mcp subcommand "${args.first}". Try `/mcp` or `/mcp list`.';
  }

  // ── panel form ─────────────────────────────────────────────────────────

  void _openPanel() {
    final servers = ctx.mcpPool.servers.toList();
    if (servers.isEmpty) {
      ctx.conversation.notify(
        'No MCP servers configured. Add some under `mcp.servers:` in your config.yaml.',
      );
      return;
    }

    final table = ResponsiveTable<McpServerSnapshot>(
      columns: const [
        TableColumn(key: 'id', header: 'ID', minWidth: 8),
        TableColumn(key: 'kind', header: 'KIND', minWidth: 8),
        TableColumn(key: 'state', header: 'STATE', minWidth: 14),
        TableColumn(
          key: 'tools',
          header: 'TOOLS',
          align: TableAlign.right,
          minWidth: 5,
        ),
        TableColumn(key: 'detail', header: 'DETAIL', minWidth: 12),
      ],
      rows: servers,
      gap: ' ',
      includeHeaderInWidth: true,
      getValues: (s) => {
        'id': s.id.styled.cyan.toString(),
        'kind': _kindLabel(s.spec),
        'state': _stateLabel(s.state).styled.dim.toString(),
        'tools': s.toolCount.toString(),
        'detail': (s.lastError ?? _detailFor(s.spec)).styled.dim.toString(),
      },
    );

    final options = <SelectOption<McpServerSnapshot>>[];
    for (var i = 0; i < servers.length; i++) {
      final s = servers[i];
      options.add(
        SelectOption.responsive(
          value: s,
          build: (w) => table.renderRow(i, w),
          searchText: '${s.id} ${_kindLabel(s.spec)} ${_stateLabel(s.state)}',
        ),
      );
    }

    final panel = SelectPanel<McpServerSnapshot>(
      title: 'MCP servers',
      options: options,
      headerBuilder: table.renderHeader,
      searchHint: 'filter servers',
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.8, 60),
      height: PanelFluid(0.6, 8),
    );
    ctx.panels.push(panel);
    // v1: selection is read-only. Toggle / reconnect / call actions land
    // in B7 as a follow-up action panel.
    panel.selection.then((_) => ctx.panels.dismiss(panel));
  }

  // ── text form ──────────────────────────────────────────────────────────

  String _textList() {
    final servers = ctx.mcpPool.servers.toList();
    if (servers.isEmpty) {
      return 'No MCP servers configured. Add some under `mcp.servers:` '
          'in your config.yaml.';
    }
    final lines = <String>['MCP servers:'];
    for (final s in servers) {
      lines.add('  ${s.id.padRight(20)} '
          '${_stateLabel(s.state)}  '
          '(${s.toolCount} tool${s.toolCount == 1 ? '' : 's'})');
      if (s.lastError != null) {
        lines.add('    last error: ${s.lastError}');
      }
    }
    return lines.join('\n');
  }

  // ── helpers ────────────────────────────────────────────────────────────

  String _kindLabel(McpServerSpec spec) => switch (spec) {
        McpStdioServerSpec() => 'stdio',
        McpHttpServerSpec() => 'http+sse',
        McpWebSocketServerSpec() => 'websocket',
      };

  String _stateLabel(McpConnectionState state) => switch (state) {
        McpDisconnected() => 'disconnected',
        McpConnecting() => 'connecting',
        McpConnected(:final serverName) => 'connected ($serverName)',
        McpReconnecting(:final attempt) => 'reconnecting (#$attempt)',
        McpDead(:final reason) => 'dead — $reason',
      };

  String _detailFor(McpServerSpec spec) => switch (spec) {
        McpStdioServerSpec(:final command) => command,
        McpHttpServerSpec(:final url) => url.toString(),
        McpWebSocketServerSpec(:final url) => url.toString(),
      };
}
