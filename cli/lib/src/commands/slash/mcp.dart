import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/slash_command_context.dart';
import 'package:glue/src/commands/slash_commands.dart';

/// `/mcp` — inspect MCP server state inside a running Glue session.
///
/// Sub-actions land in B7 (toggle, reconnect, call, auth login/logout).
/// v1 (this bundle) is read-only: `/mcp` / `/mcp list` print one row per
/// configured server with its connection state and tool count.
class McpSlashCommand extends SlashCommand {
  McpSlashCommand(this.ctx);

  final SlashCommandContext ctx;

  @override
  String get name => 'mcp';

  @override
  String get description => 'Inspect MCP servers';

  @override
  String execute(List<String> args) {
    if (args.isEmpty || args.first == 'list') {
      return _list();
    }
    return 'Unknown /mcp subcommand "${args.first}". Try `/mcp` or `/mcp list`.';
  }

  String _list() {
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

  String _stateLabel(McpConnectionState state) => switch (state) {
        McpDisconnected() => 'disconnected',
        McpConnecting() => 'connecting',
        McpConnected(:final serverName) => 'connected ($serverName)',
        McpReconnecting(:final attempt) => 'reconnecting (#$attempt)',
        McpDead(:final reason) => 'dead — $reason',
      };
}
