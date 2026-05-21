/// Top-level `glue mcp …` subcommands.
///
/// CLI-side surface is intentionally light — without a running session
/// we can only inspect config + credentials, not live pool state. The
/// `/mcp …` slash commands (cli/lib/src/commands/slash/mcp.dart) mirror
/// these but show live pool state because they run inside the TUI.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue/src/commands/config_command.dart' show userConfigPath;
import 'package:glue/src/commands/mcp_auth_status_format.dart';
import 'package:glue/src/commands/mcp_list_format.dart';
import 'package:glue/src/commands/mcp_tools_format.dart';
import 'package:glue/src/terminal/brand.dart';
import 'package:glue/src/terminal/tty_style.dart';

/// Credential-store conventions for MCP. Both helpers and slash commands
/// go through here so the namespacing stays consistent.
abstract final class McpCredentialKeys {
  /// CredentialStore provider id namespace for a given server.
  static String providerId(String serverId) => 'mcp:$serverId';

  /// Field name for the bearer token.
  static const String bearer = 'bearer';
}

class McpCommand extends Command<int> {
  McpCommand() {
    addSubcommand(McpAddCommand());
    addSubcommand(McpRemoveCommand());
    addSubcommand(McpEnableCommand());
    addSubcommand(McpDisableCommand());
    addSubcommand(McpListCommand());
    addSubcommand(McpToolsCommand());
    addSubcommand(McpAuthCommand());
  }

  @override
  String get name => 'mcp';

  @override
  String get description => 'Manage Model Context Protocol (MCP) servers.';
}

// ─── add / remove / enable / disable ───────────────────────────────────────

/// Server-id grammar: lowercase alphanumeric + `_` / `-`, starting with an
/// alphanumeric. Same shape we use to namespace tools (`<id>.<tool>`) and
/// credentials (`mcp:<id>`).
final _serverIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

class McpAddCommand extends Command<int> {
  McpAddCommand() {
    argParser
      ..addOption(
        'transport',
        abbr: 't',
        allowed: ['stdio', 'http', 'ws'],
        help: 'Wire protocol. Required.',
      )
      ..addOption('url', help: 'URL for http/ws transports.')
      ..addOption(
        'auth',
        allowed: ['none', 'bearer', 'oauth'],
        defaultsTo: 'none',
        help:
            'Auth kind for http/ws. Use `glue mcp auth …` to store the '
            'token/run OAuth.',
      )
      ..addMultiOption(
        'env',
        abbr: 'e',
        help:
            'Environment variable to pass to a stdio subprocess '
            '(KEY=value, repeatable).',
      )
      ..addOption('cwd', help: 'Working directory for a stdio subprocess.')
      ..addOption(
        'timeout',
        help:
            'Per-call timeout in seconds. Overrides mcp.call_timeout_seconds.',
      )
      ..addFlag(
        'disabled',
        negatable: false,
        help: 'Start parked. Use `glue mcp enable <id>` to turn on.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing server entry with the same id.',
      );
  }

  @override
  String get name => 'add';

  @override
  String get description => [
    'Add a new MCP server entry to ~/.glue/config.yaml.',
    '',
    'Examples:',
    '  # 1. Local stdio via npx (Playwright browser automation)',
    '  glue mcp add playwright --transport stdio \\',
    '    -- npx -y @playwright/mcp@latest',
    '',
    '  # 2. Local stdio via docker (GitHub server, PAT in env)',
    '  glue mcp add github --transport stdio \\',
    '    -e GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxx \\',
    '    -- docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN \\',
    '       ghcr.io/github/github-mcp-server',
    '',
    '  # 3. Hosted HTTP, no auth (Context7 docs lookup)',
    '  glue mcp add context7 --transport http \\',
    '    --url https://mcp.context7.com/mcp',
    '',
    '  # 4. Hosted HTTP with a bearer token (GitHub Copilot MCP)',
    '  glue mcp add github-hosted --transport http \\',
    '    --url https://api.githubcopilot.com/mcp/ --auth bearer',
    '  glue mcp auth set github-hosted --bearer    # then store the PAT',
    '',
    '  # 5. Hosted HTTP with OAuth (when the server advertises DCR)',
    '  glue mcp add some-saas --transport http \\',
    '    --url https://mcp.example.com --auth oauth',
    '  glue mcp auth login some-saas               # opens browser',
  ].join('\n');

  @override
  String get invocation =>
      'glue mcp add <id> --transport stdio|http|ws [options] [-- <cmd> <args>...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.isEmpty) {
      stderr.writeln('Usage: $invocation');
      return 1;
    }
    final id = results.rest.first;
    final commandRest = results.rest.skip(1).toList();

    if (!_serverIdPattern.hasMatch(id)) {
      stderr.writeln(
        'Invalid id "$id". Use lowercase letters, digits, "_" and "-" '
        '(must start with a letter or digit).',
      );
      return 1;
    }

    final transport = results.option('transport');
    if (transport == null) {
      stderr.writeln('--transport is required (stdio | http | ws).');
      return 1;
    }

    final env = Environment.detect();
    final spec = _buildSpec(id, transport, commandRest, results);
    if (spec == null) return 1; // _buildSpec already printed the reason

    final writer = McpConfigWriter(userConfigPath(env));
    try {
      writer.addServer(spec, overwrite: results.flag('force'));
    } on McpConfigWriteError catch (e) {
      stderr.writeln(e.message);
      return 1;
    }

    final shape = switch (spec) {
      McpStdioServerSpec() => 'stdio',
      McpHttpServerSpec() => 'http',
      McpWebSocketServerSpec() => 'websocket',
    };
    final ansi = stdoutSupportsAnsi();
    final boldId = styledOrPlain('"$id"', (s) => s.bold, ansiEnabled: ansi);
    final prefix = ansi ? '$markerOk ' : '';
    stdout.writeln('${prefix}Added $shape server $boldId.');
    final hint = !spec.enabled
        ? '(disabled — enable with "glue mcp enable $id")'
        : 'Run "glue" to load it.';
    stdout.writeln(styledOrPlain(hint, (s) => s.gray, ansiEnabled: ansi));
    if (spec is McpHttpServerSpec && spec.auth is McpBearerAuth) {
      stdout.writeln(
        styledOrPlain(
          'Auth set to bearer. Store the token with '
          '"glue mcp auth set $id --bearer".',
          (s) => s.gray,
          ansiEnabled: ansi,
        ),
      );
    } else if (spec is McpHttpServerSpec && spec.auth is McpOAuthAuth) {
      stdout.writeln(
        styledOrPlain(
          'Auth set to OAuth. Sign in with "glue mcp auth login $id".',
          (s) => s.gray,
          ansiEnabled: ansi,
        ),
      );
    }
    return 0;
  }

  McpServerSpec? _buildSpec(
    String id,
    String transport,
    List<String> commandRest,
    ArgResults results,
  ) {
    final enabled = !results.flag('disabled');
    final timeout = _parseTimeout(results.option('timeout'));
    if (timeout == _timeoutError) return null;

    switch (transport) {
      case 'stdio':
        if (results.option('url') != null) {
          stderr.writeln('--url is only valid for --transport http|ws.');
          return null;
        }
        if (commandRest.isEmpty) {
          stderr.writeln(
            'stdio transport needs a command after `--`. Example:\n'
            '  glue mcp add foo --transport stdio -- node server.js',
          );
          return null;
        }
        final envMap = <String, String>{};
        for (final raw in results.multiOption('env')) {
          final eq = raw.indexOf('=');
          if (eq <= 0) {
            stderr.writeln(
              "Invalid --env '$raw'. Use KEY=value (KEY non-empty).",
            );
            return null;
          }
          envMap[raw.substring(0, eq)] = raw.substring(eq + 1);
        }
        return McpStdioServerSpec(
          id: id,
          command: commandRest.first,
          args: commandRest.skip(1).toList(),
          env: envMap,
          workingDirectory: results.option('cwd'),
          enabled: enabled,
          callTimeoutSeconds: timeout,
        );
      case 'http':
      case 'ws':
        final urlOption = results.option('url');
        if (urlOption == null) {
          stderr.writeln('--url is required for --transport $transport.');
          return null;
        }
        if (commandRest.isNotEmpty) {
          stderr.writeln(
            '$transport transport does not take a positional command. '
            'Drop the `--` separator.',
          );
          return null;
        }
        if (results.multiOption('env').isNotEmpty ||
            results.option('cwd') != null) {
          stderr.writeln(
            '--env and --cwd are only valid for --transport stdio.',
          );
          return null;
        }
        final url = Uri.tryParse(urlOption);
        if (url == null) {
          stderr.writeln("--url '$urlOption' is not a valid URI.");
          return null;
        }
        final isWs = transport == 'ws';
        final schemeOk = isWs
            ? (url.scheme == 'ws' || url.scheme == 'wss')
            : (url.scheme == 'http' || url.scheme == 'https');
        if (!schemeOk) {
          stderr.writeln(
            "--url scheme '${url.scheme}' does not match --transport $transport.",
          );
          return null;
        }
        final auth = switch (results.option('auth')) {
          'bearer' => const McpBearerAuth(),
          'oauth' => const McpOAuthAuth(),
          _ => const McpNoAuth(),
        };
        if (isWs) {
          return McpWebSocketServerSpec(
            id: id,
            url: url,
            auth: auth,
            enabled: enabled,
            callTimeoutSeconds: timeout,
          );
        }
        return McpHttpServerSpec(
          id: id,
          url: url,
          auth: auth,
          enabled: enabled,
          callTimeoutSeconds: timeout,
        );
    }
    return null;
  }

  static const int _timeoutError = -999;
  int? _parseTimeout(String? raw) {
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) {
      stderr.writeln("--timeout must be a positive integer (got '$raw').");
      return _timeoutError;
    }
    return value;
  }
}

class McpRemoveCommand extends Command<int> {
  McpRemoveCommand() {
    argParser.addFlag(
      'keep-credentials',
      negatable: false,
      help: 'Leave stored credentials in place. Default: clear them.',
    );
  }

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove an MCP server entry from config.';

  @override
  String get invocation => 'glue mcp remove <id> [--keep-credentials]';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      stderr.writeln('Usage: $invocation');
      return 1;
    }
    final id = results.rest.single;
    final env = Environment.detect();
    final writer = McpConfigWriter(userConfigPath(env));

    try {
      writer.removeServer(id);
    } on McpConfigWriteError catch (e) {
      stderr.writeln(e.message);
      return 1;
    }
    stdout.writeln("Removed server '$id'.");

    if (!results.flag('keep-credentials')) {
      final credentials = CredentialStore(
        path: env.credentialsPath,
        env: Platform.environment,
      );
      _clearMcpCredentials(id, credentials);
      stdout.writeln('Credentials cleared.');
    }
    return 0;
  }
}

class McpEnableCommand extends Command<int> {
  @override
  String get name => 'enable';

  @override
  String get description => 'Enable a configured MCP server.';

  @override
  String get invocation => 'glue mcp enable <id>';

  @override
  Future<int> run() async => _setEnabled(argResults!, enabled: true);
}

class McpDisableCommand extends Command<int> {
  @override
  String get name => 'disable';

  @override
  String get description =>
      'Disable a configured MCP server without removing it.';

  @override
  String get invocation => 'glue mcp disable <id>';

  @override
  Future<int> run() async => _setEnabled(argResults!, enabled: false);
}

Future<int> _setEnabled(ArgResults results, {required bool enabled}) async {
  if (results.rest.length != 1) {
    stderr.writeln('Usage: glue mcp ${enabled ? 'enable' : 'disable'} <id>');
    return 1;
  }
  final id = results.rest.single;
  final env = Environment.detect();
  final writer = McpConfigWriter(userConfigPath(env));
  try {
    writer.setEnabled(id, enabled);
  } on McpConfigWriteError catch (e) {
    stderr.writeln(e.message);
    return 1;
  }
  stdout.writeln(
    enabled
        ? "Enabled '$id'. Will connect on next session start."
        : "Disabled '$id'.",
  );
  return 0;
}

/// Forgets bearer + OAuth credentials for [serverId]. Shared between
/// `mcp auth logout` and `mcp remove`.
void _clearMcpCredentials(String serverId, CredentialStore credentials) {
  clearMcpOAuthTokens(serverId: serverId, credentials: credentials);
  final providerId = McpCredentialKeys.providerId(serverId);
  final existing = credentials.getFields(providerId);
  final cleaned = <String, String>{
    for (final e in existing.entries)
      if (e.key != McpCredentialKeys.bearer) e.key: e.value,
  };
  credentials.setFields(providerId, cleaned);
}

class McpToolsCommand extends Command<int> {
  @override
  String get name => 'tools';

  @override
  String get description =>
      'List tools advertised by configured MCP servers (one-shot).';

  @override
  String get invocation => 'glue mcp tools [<server>]';

  @override
  Future<int> run() async {
    final argResults = this.argResults!;
    if (argResults.rest.length > 1) {
      stderr.writeln('Usage: glue mcp tools [<server>]');
      return 1;
    }

    final config = _safeLoadConfig();
    if (config == null) return 1;

    final selected = argResults.rest.isEmpty
        ? config.mcp.servers
        : config.mcp.servers
              .where((s) => s.id == argResults.rest.single)
              .toList();

    if (argResults.rest.isNotEmpty && selected.isEmpty) {
      final serverId = argResults.rest.single;
      stderr.writeln(
        'Server "$serverId" is not in your config. Known: '
        '${config.mcp.servers.map((s) => s.id).join(", ")}.',
      );
      return 1;
    }

    // Single-server form preserves the legacy "disabled → error" UX so
    // scripts can still treat it as a hard failure.
    if (argResults.rest.isNotEmpty && !selected.single.enabled) {
      final serverId = selected.single.id;
      stderr.writeln(
        'Server "$serverId" is disabled — enable it with '
        '"glue mcp enable $serverId" before listing its tools.',
      );
      return 1;
    }

    if (selected.isEmpty) {
      stdout.writeln(formatMcpToolsByServer(const []));
      return 0;
    }

    // Pool is built from `selected` (not just enabled) so the snapshots
    // we read back cover every server we plan to print — disabled ones
    // included. `connectAll()` skips disabled specs internally.
    final pool = McpClientPool(
      config: McpConfig(servers: selected),
      credentials: config.credentials,
    );
    pool.connectAll();

    final pending = selected.where((s) => s.enabled).map((s) => s.id).toSet();
    if (pending.isNotEmpty) {
      try {
        await pool.events
            .where((e) {
              if (e is McpPoolServerConnectedEvent) pending.remove(e.serverId);
              if (e is McpPoolServerErrorEvent) pending.remove(e.serverId);
              return pending.isEmpty;
            })
            .first
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        // Print whatever we got; servers still pending will show as
        // connecting/dead per their last snapshot.
      }
    }

    final listings = selected
        .map((spec) => pool.server(spec.id))
        .whereType<McpServerSnapshot>()
        .map(listingFromSnapshot)
        .toList();
    stdout.writeln(formatMcpToolsByServer(listings));
    await pool.close();
    return 0;
  }
}

class McpListCommand extends Command<int> {
  @override
  String get name => 'list';

  @override
  String get description => 'List configured MCP servers.';

  @override
  Future<int> run() async {
    final config = _safeLoadConfig();
    if (config == null) return 1;

    final rows = config.mcp.servers
        .map(
          (spec) => McpServerListRow(
            id: spec.id,
            kind: switch (spec) {
              McpStdioServerSpec() => 'stdio',
              McpHttpServerSpec() => 'http+sse',
              McpWebSocketServerSpec() => 'websocket',
            },
            enabled: spec.enabled,
          ),
        )
        .toList();
    stdout.writeln(
      formatMcpServerList(
        rows,
        configPath: userConfigPath(Environment.detect()),
      ),
    );
    return 0;
  }
}

// ─── auth subcommands ──────────────────────────────────────────────────────

class McpAuthCommand extends Command<int> {
  McpAuthCommand() {
    addSubcommand(McpAuthSetCommand());
    addSubcommand(McpAuthLoginCommand());
    addSubcommand(McpAuthLogoutCommand());
    addSubcommand(McpAuthStatusCommand());
  }

  @override
  String get name => 'auth';

  @override
  String get description => 'Manage credentials for MCP servers.';
}

class McpAuthStatusCommand extends Command<int> {
  @override
  String get name => 'status';

  @override
  String get description =>
      'Print what credentials are stored for each MCP server.';

  @override
  Future<int> run() async {
    final config = _safeLoadConfig();
    if (config == null) return 1;

    final rows = config.mcp.servers.map((spec) {
      final fields = config.credentials.getFields(
        McpCredentialKeys.providerId(spec.id),
      );
      final hasBearer = fields.containsKey(McpCredentialKeys.bearer);
      final hasOAuth = fields.containsKey(McpOAuthFields.accessToken);
      final authKind = spec is McpHttpServerSpec
          ? spec.auth
          : spec is McpWebSocketServerSpec
          ? spec.auth
          : const McpNoAuth();
      final (kind, state) = switch (authKind) {
        McpBearerAuth() => (
          'bearer',
          hasBearer ? McpAuthState.stored : McpAuthState.missing,
        ),
        McpOAuthAuth() => (
          'oauth',
          hasOAuth ? McpAuthState.stored : McpAuthState.notLoggedIn,
        ),
        McpNoAuth() => ('none', McpAuthState.none),
      };
      return McpAuthStatusRow(id: spec.id, kind: kind, state: state);
    }).toList();

    stdout.writeln(formatMcpAuthStatus(rows));
    return 0;
  }
}

class McpAuthSetCommand extends Command<int> {
  McpAuthSetCommand() {
    argParser.addFlag(
      'bearer',
      negatable: false,
      help: 'Store a bearer token. Read from stdin (one line).',
    );
  }

  @override
  String get name => 'set';

  @override
  String get description =>
      'Store a credential for an MCP server (e.g. `glue mcp auth set <server> --bearer`).';

  @override
  String get invocation => 'glue mcp auth set <server> --bearer';

  @override
  Future<int> run() async {
    final argResults = this.argResults!;
    if (argResults.rest.isEmpty) {
      stderr.writeln('Usage: glue mcp auth set <server> --bearer');
      return 1;
    }
    if (argResults.rest.length > 1) {
      stderr.writeln(
        'Too many arguments. Usage: glue mcp auth set <server> --bearer',
      );
      return 1;
    }
    if (!argResults.flag('bearer')) {
      stderr.writeln('At least one auth kind required (e.g. --bearer).');
      return 1;
    }
    final serverId = argResults.rest.single;

    final config = _safeLoadConfig();
    if (config == null) return 1;

    final knownIds = config.mcp.servers.map((s) => s.id).toSet();
    if (!knownIds.contains(serverId)) {
      stderr.writeln(
        'Server "$serverId" is not in your config. Known servers: '
        '${knownIds.isEmpty ? '(none)' : knownIds.join(", ")}.',
      );
      return 1;
    }

    stdout.write('Enter bearer token (input hidden): ');
    final token = _readSecret();
    stdout.writeln('');
    if (token.isEmpty) {
      stderr.writeln('Empty token. Aborted.');
      return 1;
    }

    config.credentials.setFields(McpCredentialKeys.providerId(serverId), {
      McpCredentialKeys.bearer: token,
    });
    stdout.writeln('Stored bearer token for "$serverId".');
    return 0;
  }
}

class McpAuthLoginCommand extends Command<int> {
  @override
  String get name => 'login';

  @override
  String get description =>
      'Run the OAuth flow for an MCP server (opens your browser).';

  @override
  String get invocation => 'glue mcp auth login <server>';

  @override
  Future<int> run() async {
    final argResults = this.argResults!;
    if (argResults.rest.length != 1) {
      stderr.writeln('Usage: glue mcp auth login <server>');
      return 1;
    }
    final serverId = argResults.rest.single;

    final config = _safeLoadConfig();
    if (config == null) return 1;

    final spec = config.mcp.servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => throw StateError(''),
    );
    if (spec is! McpHttpServerSpec && spec is! McpWebSocketServerSpec) {
      stderr.writeln(
        'OAuth is only supported for HTTP/WS servers. "$serverId" is stdio.',
      );
      return 1;
    }
    final baseUrl = spec is McpHttpServerSpec
        ? spec.url
        : (spec as McpWebSocketServerSpec).url;
    final cachedMeta = spec is McpHttpServerSpec
        ? spec.resourceMetadataUrl
        : (spec as McpWebSocketServerSpec).resourceMetadataUrl;

    final runner = McpAuthFlowRunner(
      serverId: serverId,
      serverUrl: baseUrl,
      credentials: config.credentials,
      cachedResourceMetadataUrl: cachedMeta,
      openBrowser: _openBrowser,
    );
    runner.states.listen((state) {
      switch (state) {
        case McpAuthFlowDiscovering():
          stdout.writeln('Discovering OAuth metadata for $serverId…');
        case McpAuthFlowRegistering():
          stdout.writeln('Registering OAuth client (DCR)…');
        case McpAuthFlowAwaitingCallback(:final authUrl):
          stdout.writeln('Open this URL to sign in: $authUrl');
        case McpAuthFlowSuccess(
            :final resourceMetadataUrl,
            :final authorizationServer,
          ):
          stdout.writeln('Stored OAuth tokens for "$serverId".');
          try {
            final writer = McpConfigWriter(
              userConfigPath(Environment.detect()),
            );
            writer.updateAuth(
              serverId,
              auth: const McpOAuthAuth(),
              resourceMetadataUrl: resourceMetadataUrl,
              authorizationServer: authorizationServer,
            );
          } on McpConfigWriteError catch (e) {
            stderr.writeln(
              'Warning: could not update config.yaml: ${e.message}',
            );
          }
        case McpAuthFlowError(:final message):
          stderr.writeln('OAuth login failed: $message');
        case McpAuthFlowCancelled():
          stderr.writeln('Cancelled.');
      }
    });

    try {
      final terminal = await runner.run();
      return terminal is McpAuthFlowSuccess ? 0 : 1;
    } on StateError {
      stderr.writeln(
        'Server "$serverId" is not in your config. '
        'Known: ${config.mcp.servers.map((s) => s.id).join(", ")}.',
      );
      return 1;
    }
  }
}

class McpAuthLogoutCommand extends Command<int> {
  @override
  String get name => 'logout';

  @override
  String get description => 'Forget stored credentials for an MCP server.';

  @override
  String get invocation => 'glue mcp auth logout <server>';

  @override
  Future<int> run() async {
    final argResults = this.argResults!;
    if (argResults.rest.length != 1) {
      stderr.writeln('Usage: glue mcp auth logout <server>');
      return 1;
    }
    final serverId = argResults.rest.single;

    final config = _safeLoadConfig();
    if (config == null) return 1;

    _clearMcpCredentials(serverId, config.credentials);
    stdout.writeln('Forgot credentials for "$serverId".');
    return 0;
  }
}

// ─── helpers ───────────────────────────────────────────────────────────────

GlueConfig? _safeLoadConfig() {
  try {
    return GlueConfig.load(environment: Environment.detect());
  } on ConfigError catch (e) {
    stderr.writeln('Failed to load config: ${e.message}');
    return null;
  }
}

Future<void> _openBrowser(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start('rundll32', [
        'url.dll,FileProtocolHandler',
        url,
      ], mode: ProcessStartMode.detached);
    }
  } catch (_) {
    // User can copy-paste — we already printed the URL.
  }
}

/// Reads a single line from stdin without echoing. Falls back to plain
/// readLineSync on platforms where echoMode isn't available.
String _readSecret() {
  final hadEcho = stdin.echoMode;
  try {
    stdin.echoMode = false;
  } catch (_) {
    // Some terminals don't support echoMode; fall through with echo on.
  }
  try {
    final line = stdin.readLineSync();
    return line?.trim() ?? '';
  } finally {
    try {
      stdin.echoMode = hadEcho;
    } catch (_) {}
  }
}
