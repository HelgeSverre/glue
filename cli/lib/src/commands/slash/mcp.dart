import 'dart:async';

import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/arg_completers.dart' as arg_completers;
import 'package:glue/src/commands/config_command.dart' show userConfigPath;
import 'package:glue/src/commands/mcp_tools_format.dart';
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
  SlashArgCompleter? get argCompleter => (prior, partial) {
    // /mcp <TAB>
    if (prior.isEmpty) {
      return arg_completers.mcpSubcommandCandidates(partial);
    }
    final servers = ctx.mcpPool.servers;
    // /mcp tools|reconnect|toggle <TAB>
    if (prior.length == 1 &&
        const {'tools', 'reconnect', 'toggle'}.contains(prior.first)) {
      return arg_completers.mcpServerIdCandidates(servers, partial);
    }
    // /mcp auth <TAB>
    if (prior.length == 1 && prior.first == 'auth') {
      return arg_completers.mcpAuthSubcommandCandidates(partial);
    }
    // /mcp auth login|logout <TAB> — HTTP/WS servers only.
    if (prior.length == 2 &&
        prior.first == 'auth' &&
        const {'login', 'logout'}.contains(prior[1])) {
      return arg_completers.mcpServerIdCandidates(
        servers,
        partial,
        requireRemote: true,
      );
    }
    return const [];
  };

  @override
  String execute(List<String> args) {
    if (args.isEmpty) {
      _openPanel();
      return '';
    }
    switch (args.first) {
      case 'list':
        return _textList();
      case 'tools':
        return _tools(args.skip(1).toList());
      case 'reconnect':
        return _reconnect(args.skip(1).toList());
      case 'toggle':
        return _toggle(args.skip(1).toList());
      case 'auth':
        return _auth(args.skip(1).toList());
      case 'help':
      case '--help':
      case '-h':
        return _help();
      default:
        return 'Unknown /mcp subcommand "${args.first}". '
            'Try `/mcp help`.';
    }
  }

  String _help() => [
    '/mcp                            Open the status panel.',
    '/mcp list                       Print a text table inline.',
    '/mcp tools [<server>]           List tools (grouped by server if no arg).',
    '/mcp reconnect <server>         Retry a dead/reconnecting server.',
    '/mcp toggle <server>            Session-scoped enable/disable.',
    '/mcp auth login <server>        Run the OAuth flow (HTTP/WS only).',
    '/mcp auth logout <server>       Forget stored credentials.',
    '/mcp auth status                Show credential state per server.',
  ].join('\n');

  // ── tools / reconnect / toggle ─────────────────────────────────────────

  String _tools(List<String> args) {
    if (args.length > 1) return 'Usage: /mcp tools [<server>]';
    if (args.isEmpty) {
      return formatMcpToolsByServer(
        ctx.mcpPool.servers.map(listingFromSnapshot),
      );
    }
    final s = ctx.mcpPool.server(args.single);
    if (s == null) return 'Server "${args.single}" is not in your config.';
    return formatMcpToolsByServer([listingFromSnapshot(s)]);
  }

  String _reconnect(List<String> args) {
    if (args.length != 1) return 'Usage: /mcp reconnect <server>';
    final s = ctx.mcpPool.server(args.single);
    if (s == null) return 'Server "${args.single}" is not in your config.';
    ctx.mcpPool.reconnect(s.id);
    return 'Reconnecting "${s.id}"…';
  }

  String _toggle(List<String> args) {
    if (args.length != 1) return 'Usage: /mcp toggle <server>';
    final s = ctx.mcpPool.server(args.single);
    if (s == null) return 'Server "${args.single}" is not in your config.';
    final wasEnabled = s.enabled;
    ctx.mcpPool.toggle(s.id);
    return wasEnabled
        ? 'Disabling "${s.id}" for this session…'
        : 'Enabling "${s.id}" and connecting…';
  }

  // ── auth subcommands ───────────────────────────────────────────────────

  String _auth(List<String> args) {
    if (args.isEmpty) {
      return 'Usage: /mcp auth login <server> | logout <server> | status';
    }
    switch (args.first) {
      case 'login':
        return _authLogin(args.skip(1).toList());
      case 'logout':
        return _authLogout(args.skip(1).toList());
      case 'status':
        return _authStatus();
      default:
        return 'Unknown /mcp auth subcommand "${args.first}". '
            'Try `login`, `logout`, or `status`.';
    }
  }

  String _authStatus() {
    final config = ctx.config;
    if (config == null) return 'Config not loaded.';
    final servers = ctx.mcpPool.servers.toList();
    if (servers.isEmpty) return 'No MCP servers configured.';
    final lines = <String>['MCP credentials:'];
    for (final s in servers) {
      final providerId = 'mcp:${s.id}';
      final fields = config.credentials.getFields(providerId);
      final tag = _credentialTag(s.spec, fields);
      lines.add('  ${s.id.padRight(20)} $tag');
    }
    return lines.join('\n');
  }

  String _credentialTag(McpServerSpec spec, Map<String, String> fields) {
    final hasBearer = fields.containsKey('bearer');
    final hasOAuth = fields.containsKey(McpOAuthFields.accessToken);
    final authKind = spec is McpHttpServerSpec
        ? spec.auth
        : spec is McpWebSocketServerSpec
        ? spec.auth
        : const McpNoAuth();
    return switch (authKind) {
      McpBearerAuth() => hasBearer ? 'bearer (stored)' : 'bearer (missing)',
      McpOAuthAuth() =>
        hasOAuth ? 'oauth (access token stored)' : 'oauth (not logged in)',
      McpNoAuth() => 'none',
    };
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
    final snapshot = ctx.mcpPool.server(serverId);
    final spec = snapshot?.spec;
    final cachedMeta = switch (spec) {
      McpHttpServerSpec(:final resourceMetadataUrl) => resourceMetadataUrl,
      McpWebSocketServerSpec(:final resourceMetadataUrl) => resourceMetadataUrl,
      _ => null,
    };

    final runner = McpAuthFlowRunner(
      serverId: serverId,
      serverUrl: baseUrl,
      credentials: credentials,
      cachedResourceMetadataUrl: cachedMeta,
      openBrowser: openInBrowser,
    );

    runner.states.listen((state) {
      switch (state) {
        case McpAuthFlowDiscovering():
          ctx.conversation.notify(
            'Discovering OAuth metadata for "$serverId"…',
          );
        case McpAuthFlowRegistering():
          ctx.conversation.notify('Registering OAuth client (DCR)…');
        case McpAuthFlowAwaitingCallback(:final authUrl):
          ctx.conversation.notify('Open in your browser: $authUrl');
        case McpAuthFlowSuccess(
          :final resourceMetadataUrl,
          :final authorizationServer,
        ):
          ctx.conversation.notify('Signed in to "$serverId". Reconnecting…');
          _writeBackAuthConfig(
            serverId,
            resourceMetadataUrl,
            authorizationServer,
          );
          ctx.mcpPool.reconnect(serverId);
        case McpAuthFlowError(:final message):
          ctx.conversation.notify('OAuth failed for "$serverId": $message');
        case McpAuthFlowCancelled():
          ctx.conversation.notify('OAuth cancelled for "$serverId".');
      }
    });

    // Fire and forget — state listener handles all outcomes.
    unawaited(runner.run());
  }

  void _writeBackAuthConfig(
    String serverId,
    Uri? resourceMetadataUrl,
    Uri? authorizationServer,
  ) {
    try {
      final writer = McpConfigWriter(userConfigPath(Environment.detect()));
      writer.updateAuth(
        serverId,
        auth: const McpOAuthAuth(),
        resourceMetadataUrl: resourceMetadataUrl,
        authorizationServer: authorizationServer,
      );
    } catch (_) {
      // Non-fatal — tokens are already stored. Surface a soft warning.
      ctx.conversation.notify(
        'Tokens stored, but could not update config.yaml '
        '(auth state may not persist between sessions).',
      );
    }
  }

  String _authLogout(List<String> args) {
    if (args.length != 1) return 'Usage: /mcp auth logout <server>';
    final serverId = args.single;
    final config = ctx.config;
    if (config == null) return 'Config not loaded.';
    clearMcpOAuthTokens(serverId: serverId, credentials: config.credentials);
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
    panel.selection.then((picked) {
      if (picked == null) {
        ctx.panels.dismiss(panel);
        return;
      }
      _openActionPanel(parentPanel: panel, server: picked);
    });
  }

  void _openActionPanel({
    required SelectPanel<McpServerSnapshot> parentPanel,
    required McpServerSnapshot server,
  }) {
    final actions = _actionsFor(server);
    final lines = actions.map((a) => a.label(server)).toList();
    final actionPanel = PanelModal(
      title: server.id,
      lines: lines,
      barrier: BarrierStyle.dim,
      height: PanelFixed(lines.length + 2),
      width: PanelFixed(36),
      selectable: true,
    );
    ctx.panels.push(actionPanel);

    actionPanel.selection.then((idx) async {
      ctx.panels.dismiss(actionPanel);
      ctx.panels.dismiss(parentPanel);
      if (idx == null) return;
      final action = actions[idx];
      switch (action) {
        case _McpAction.authenticate:
        case _McpAction.reauthenticate:
          final result = _authLogin([server.id]);
          if (result.isNotEmpty) ctx.conversation.notify(result);
        case _McpAction.signOut:
          final result = _authLogout([server.id]);
          if (result.isNotEmpty) ctx.conversation.notify(result);
        case _McpAction.reconnect:
          ctx.mcpPool.reconnect(server.id);
          ctx.conversation.notify('Reconnecting "${server.id}"…');
        case _McpAction.toggle:
          final wasEnabled = server.enabled;
          ctx.mcpPool.toggle(server.id);
          ctx.conversation.notify(
            wasEnabled
                ? 'Disabling "${server.id}" for this session…'
                : 'Enabling "${server.id}" and connecting…',
          );
        case _McpAction.viewTools:
          _openToolsPanel(server);
        case _McpAction.copyId:
          final ok = await copyToClipboard(server.id);
          ctx.conversation.notify(
            ok
                ? 'Copied "${server.id}" to clipboard.'
                : 'Clipboard copy failed on this platform.',
          );
        case _McpAction.showError:
          _openErrorPanel(server);
      }
    });
  }

  void _openToolsPanel(McpServerSnapshot server) {
    if (server.tools.isEmpty) {
      ctx.conversation.notify(
        server.state is McpConnected
            ? 'Server "${server.id}" advertises no tools.'
            : 'Server "${server.id}" is not connected; tools unknown.',
      );
      return;
    }
    final lines = <String>[
      for (final t in server.tools)
        t.description.isEmpty ? t.name : '${t.name}  — ${t.description}',
    ];
    final panel = PanelModal(
      title: 'Tools — ${server.id}',
      lines: lines,
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.7, 40),
      height: PanelFluid(0.6, 6),
      selectable: false,
    );
    ctx.panels.push(panel);
    panel.result.then((_) => ctx.panels.dismiss(panel));
  }

  void _openErrorPanel(McpServerSnapshot server) {
    final err = server.lastError ?? '(no error recorded)';
    final panel = PanelModal(
      title: 'Last error — ${server.id}',
      lines: err.split('\n'),
      barrier: BarrierStyle.dim,
      width: PanelFluid(0.7, 40),
      height: PanelFluid(0.4, 4),
      selectable: false,
    );
    ctx.panels.push(panel);
    panel.result.then((_) => ctx.panels.dismiss(panel));
  }

  List<_McpAction> _actionsFor(McpServerSnapshot s) {
    final isRemote =
        s.spec is McpHttpServerSpec || s.spec is McpWebSocketServerSpec;
    final hasAccessToken =
        isRemote &&
        ctx.config != null &&
        ctx.config!.credentials.getField(
              'mcp:${s.id}',
              McpOAuthFields.accessToken,
            ) !=
            null;

    return [
      if (isRemote && (s.state is McpAwaitingAuth || !hasAccessToken))
        _McpAction.authenticate,
      if (isRemote && hasAccessToken) _McpAction.reauthenticate,
      _McpAction.reconnect,
      _McpAction.toggle,
      if (s.tools.isNotEmpty) _McpAction.viewTools,
      _McpAction.copyId,
      if (isRemote && hasAccessToken) _McpAction.signOut,
      if (s.lastError != null) _McpAction.showError,
    ];
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
      lines.add(
        '  ${s.id.padRight(20)} '
        '${_stateLabel(s.state)}  '
        '(${s.toolCount} tool${s.toolCount == 1 ? '' : 's'})${_authTag(s)}',
      );
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
    McpAwaitingAuth() => 'needs auth',
  };

  String _authTag(McpServerSnapshot s) {
    final spec = s.spec;
    if (spec is! McpHttpServerSpec && spec is! McpWebSocketServerSpec) {
      return '';
    }
    final hasToken =
        ctx.config?.credentials.getField(
          'mcp:${s.id}',
          McpOAuthFields.accessToken,
        ) !=
        null;
    final authKind = spec is McpHttpServerSpec
        ? spec.auth
        : (spec as McpWebSocketServerSpec).auth;
    return switch (authKind) {
      McpOAuthAuth() when hasToken => '  · oauth (signed in)',
      McpOAuthAuth() => '  · oauth (not signed in)',
      _ => '',
    };
  }

  String _detailFor(McpServerSpec spec) => switch (spec) {
    McpStdioServerSpec(:final command) => command,
    McpHttpServerSpec(:final url) => url.toString(),
    McpWebSocketServerSpec(:final url) => url.toString(),
  };
}

/// Returns the auth-related action labels for a server, in display
/// order. Pure helper — exposed at top-level for testability.
///
/// stdio servers always return an empty list. For HTTP/WS servers:
///   • `'Authenticate'` when no access token is stored OR the server is
///     in [McpAwaitingAuth].
///   • `'Re-authenticate'` + `'Sign out'` when an access token is
///     stored.
List<String> resolveMcpAuthActions({
  required McpServerSpec spec,
  required McpConnectionState state,
  required bool hasAccessToken,
}) {
  final isRemote = spec is McpHttpServerSpec || spec is McpWebSocketServerSpec;
  if (!isRemote) return const [];
  if (state is McpAwaitingAuth || !hasAccessToken) {
    return const ['Authenticate'];
  }
  return const ['Re-authenticate', 'Sign out'];
}

enum _McpAction {
  authenticate,
  reauthenticate,
  signOut,
  reconnect,
  toggle,
  viewTools,
  copyId,
  showError;

  String label(McpServerSnapshot s) => switch (this) {
    _McpAction.authenticate => 'Authenticate',
    _McpAction.reauthenticate => 'Re-authenticate',
    _McpAction.signOut => 'Sign out',
    _McpAction.reconnect => 'Reconnect',
    _McpAction.toggle =>
      s.enabled ? 'Disable for this session' : 'Enable and connect',
    _McpAction.viewTools => 'View tools (${s.tools.length})',
    _McpAction.copyId => 'Copy server ID',
    _McpAction.showError => 'Show last error',
  };
}
