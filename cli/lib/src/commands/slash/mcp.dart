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
    switch (args.first) {
      case 'list':
        return _textList();
      case 'auth':
        return _auth(args.skip(1).toList());
      default:
        return 'Unknown /mcp subcommand "${args.first}". '
            'Try `/mcp`, `/mcp list`, or `/mcp auth login <server>`.';
    }
  }

  // ── auth subcommands ───────────────────────────────────────────────────

  String _auth(List<String> args) {
    if (args.isEmpty) {
      return 'Usage: /mcp auth login <server> | /mcp auth logout <server>';
    }
    switch (args.first) {
      case 'login':
        return _authLogin(args.skip(1).toList());
      case 'logout':
        return _authLogout(args.skip(1).toList());
      default:
        return 'Unknown /mcp auth subcommand "${args.first}". '
            'Try `login` or `logout`.';
    }
  }

  String _authLogin(List<String> args) {
    if (args.length != 1) return 'Usage: /mcp auth login <server>';
    final serverId = args.single;
    final snapshot = ctx.mcpPool.server(serverId);
    if (snapshot == null) {
      return 'Server "$serverId" is not in your config.';
    }
    final spec = snapshot.spec;
    if (spec is! McpHttpServerSpec && spec is! McpWebSocketServerSpec) {
      return 'OAuth is only supported for HTTP/WS servers. "$serverId" is stdio.';
    }
    final baseUrl = spec is McpHttpServerSpec
        ? spec.url
        : (spec as McpWebSocketServerSpec).url;

    final config = ctx.config;
    if (config == null) return 'Config not loaded.';

    // Run the flow asynchronously and surface progress as system messages.
    _runLoginFlow(serverId, baseUrl, config.credentials);
    return 'Starting OAuth flow for "$serverId" — watch for the browser URL above.';
  }

  void _runLoginFlow(
    String serverId,
    Uri baseUrl,
    CredentialStore credentials,
  ) {
    () async {
      try {
        ctx.conversation.notify('Discovering OAuth metadata…');
        final endpoints = await discoverOAuthEndpoints(baseUrl);

        OAuthClient client;
        final existingClientId = credentials.getField(
          'mcp:$serverId',
          McpOAuthFields.clientId,
        );
        if (existingClientId != null) {
          client = OAuthClient(
            clientId: existingClientId,
            clientSecret: credentials.getField(
              'mcp:$serverId',
              McpOAuthFields.clientSecret,
            ),
          );
        } else if (endpoints.registrationEndpoint != null) {
          ctx.conversation.notify('Registering OAuth client (DCR)…');
          client = await registerOAuthClient(
            registrationEndpoint: endpoints.registrationEndpoint!,
            redirectUri: Uri.parse('http://127.0.0.1/callback'),
            clientName: 'glue',
          );
        } else {
          ctx.conversation.notify(
            'OAuth login failed: no registration_endpoint and no client_id stored.',
          );
          return;
        }

        final tokens = await runOAuthAuthorizationCodeFlow(
          endpoints: endpoints,
          client: client,
          onAuthUrl: (url) {
            ctx.conversation.notify('Open in your browser: $url');
          },
        );

        storeMcpOAuthTokens(
          serverId: serverId,
          client: client,
          tokens: tokens,
          credentials: credentials,
        );
        ctx.conversation.notify(
          'Stored OAuth tokens for "$serverId". '
          'Reconnect via `/mcp reconnect $serverId` once that command lands.',
        );
      } on Exception catch (e) {
        ctx.conversation.notify('OAuth login failed for "$serverId": $e');
      }
    }();
  }

  String _authLogout(List<String> args) {
    if (args.length != 1) return 'Usage: /mcp auth logout <server>';
    final serverId = args.single;
    final config = ctx.config;
    if (config == null) return 'Config not loaded.';
    clearMcpOAuthTokens(
      serverId: serverId,
      credentials: config.credentials,
    );
    final providerId = 'mcp:$serverId';
    final existing = config.credentials.getFields(providerId);
    final cleaned = <String, String>{
      for (final e in existing.entries)
        if (e.key != 'bearer') e.key: e.value,
    };
    config.credentials.setFields(providerId, cleaned);
    return 'Forgot credentials for "$serverId".';
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
