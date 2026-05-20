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
        help: 'Auth kind for http/ws. Use `glue mcp auth …` to store the '
            'token/run OAuth.',
      )
      ..addMultiOption(
        'env',
        abbr: 'e',
        help: 'Environment variable to pass to a stdio subprocess '
            '(KEY=value, repeatable).',
      )
      ..addOption('cwd', help: 'Working directory for a stdio subprocess.')
      ..addOption(
        'timeout',
        help: 'Per-call timeout in seconds. Overrides mcp.call_timeout_seconds.',
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
  String get description =>
      'Add a new MCP server entry to ~/.glue/config.yaml.';

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
    stdout.writeln('Added $shape server "$id".');
    if (!spec.enabled) {
      stdout.writeln('(disabled — enable with "glue mcp enable $id")');
    } else {
      stdout.writeln('Run "glue" to load it.');
    }
    if (spec is McpHttpServerSpec && spec.auth is McpBearerAuth) {
      stdout.writeln(
        'Auth set to bearer. Store the token with '
        '"glue mcp auth set $id --bearer".',
      );
    } else if (spec is McpHttpServerSpec && spec.auth is McpOAuthAuth) {
      stdout.writeln(
        'Auth set to OAuth. Sign in with "glue mcp auth login $id".',
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
    stderr.writeln(
      'Usage: glue mcp ${enabled ? 'enable' : 'disable'} <id>',
    );
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
      'Connect to an MCP server and list its tools (one-shot).';

  @override
  String get invocation => 'glue mcp tools <server>';

  @override
  Future<int> run() async {
    final argResults = this.argResults!;
    if (argResults.rest.length != 1) {
      stderr.writeln('Usage: glue mcp tools <server>');
      return 1;
    }
    final serverId = argResults.rest.single;

    final config = _safeLoadConfig();
    if (config == null) return 1;

    final spec = config.mcp.servers.where((s) => s.id == serverId).firstOrNull;
    if (spec == null) {
      stderr.writeln(
        'Server "$serverId" is not in your config. Known: '
        '${config.mcp.servers.map((s) => s.id).join(", ")}.',
      );
      return 1;
    }
    if (!spec.enabled) {
      stderr.writeln(
        'Server "$serverId" is disabled — enable it with '
        '"glue mcp enable $serverId" before listing its tools.',
      );
      return 1;
    }

    // Spin up a transient pool of just this server, wait briefly, print.
    final pool = McpClientPool(
      config: McpConfig(servers: [spec]),
      credentials: config.credentials,
    );
    pool.connectAll();

    try {
      await pool.events
          .where((e) =>
              e is McpPoolServerConnectedEvent || e is McpPoolServerErrorEvent)
          .first
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      stderr.writeln('Timed out waiting for "$serverId" to respond.');
      await pool.close();
      return 1;
    }

    final snapshot = pool.server(serverId);
    if (snapshot == null || snapshot.tools.isEmpty) {
      stderr.writeln(
        'Server "$serverId" advertised no tools (state: '
        '${snapshot?.state.runtimeType ?? 'unknown'}).',
      );
      if (snapshot?.lastError != null) {
        stderr.writeln('Last error: ${snapshot!.lastError}');
      }
      await pool.close();
      return 1;
    }
    for (final t in snapshot.tools) {
      final desc = t.description.isEmpty ? '' : ' — ${t.description}';
      stdout.writeln('  ${t.name}$desc');
    }
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

    final servers = config.mcp.servers;
    if (servers.isEmpty) {
      stdout.writeln('No MCP servers configured.');
      stdout.writeln('Add a server under `mcp.servers:` in '
          '${userConfigPath(Environment.detect())}.');
      return 0;
    }

    for (final spec in servers) {
      final kind = switch (spec) {
        McpStdioServerSpec() => 'stdio',
        McpHttpServerSpec() => 'http+sse',
        McpWebSocketServerSpec() => 'websocket',
      };
      final state = spec.enabled ? 'enabled' : 'disabled';
      stdout.writeln('  ${spec.id.padRight(20)} $kind  $state');
    }
    stdout.writeln('');
    stdout
        .writeln('Use `/mcp` inside a Glue session for live connection state.');
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

    final servers = config.mcp.servers;
    if (servers.isEmpty) {
      stdout.writeln('No MCP servers configured.');
      return 0;
    }
    for (final spec in servers) {
      final fields =
          config.credentials.getFields(McpCredentialKeys.providerId(spec.id));
      final hasBearer = fields.containsKey(McpCredentialKeys.bearer);
      final hasOAuth = fields.containsKey(McpOAuthFields.accessToken);
      final authKind = spec is McpHttpServerSpec
          ? spec.auth
          : spec is McpWebSocketServerSpec
              ? spec.auth
              : const McpNoAuth();
      final tag = switch (authKind) {
        McpBearerAuth() => hasBearer ? 'bearer (stored)' : 'bearer (missing)',
        McpOAuthAuth() =>
          hasOAuth ? 'oauth (access token stored)' : 'oauth (not logged in)',
        McpNoAuth() => 'none',
      };
      stdout.writeln('  ${spec.id.padRight(20)} $tag');
    }
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

    config.credentials.setFields(
      McpCredentialKeys.providerId(serverId),
      {McpCredentialKeys.bearer: token},
    );
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

    try {
      stdout.writeln('Discovering OAuth metadata for $serverId…');
      final endpoints = await discoverOAuthEndpoints(baseUrl);

      OAuthClient client;
      final existingClientId =
          config.credentials.getField('mcp:$serverId', McpOAuthFields.clientId);
      if (existingClientId != null) {
        client = OAuthClient(
          clientId: existingClientId,
          clientSecret: config.credentials
              .getField('mcp:$serverId', McpOAuthFields.clientSecret),
        );
        stdout.writeln('Reusing registered client_id.');
      } else if (endpoints.registrationEndpoint != null) {
        stdout.writeln('Registering OAuth client (DCR)…');
        // Loopback URI here is a stub for registration; the actual
        // redirect URI is bound at flow time. Many servers accept
        // multiple URIs at registration, so register a wildcard-shaped
        // localhost one.
        client = await registerOAuthClient(
          registrationEndpoint: endpoints.registrationEndpoint!,
          redirectUri: Uri.parse('http://127.0.0.1/callback'),
          clientName: 'glue',
        );
      } else {
        stderr.writeln(
          'No registration_endpoint advertised and no client_id stored '
          'for "$serverId". Pre-register a client out-of-band, then set '
          '`oauth_client_id` via `glue mcp auth set <server>` (not yet '
          'supported for non-DCR servers).',
        );
        return 1;
      }

      stdout.writeln('Opening browser…');
      final tokens = await runOAuthAuthorizationCodeFlow(
        endpoints: endpoints,
        client: client,
        onAuthUrl: (url) {
          stdout.writeln('Browse to: $url');
          unawaited(_openBrowser(url));
        },
      );

      storeMcpOAuthTokens(
        serverId: serverId,
        client: client,
        tokens: tokens,
        credentials: config.credentials,
      );
      stdout.writeln('Stored OAuth tokens for "$serverId".');
      return 0;
    } on StateError {
      stderr.writeln(
        'Server "$serverId" is not in your config. '
        'Known: ${config.mcp.servers.map((s) => s.id).join(", ")}.',
      );
      return 1;
    } on Exception catch (e) {
      stderr.writeln('OAuth login failed: $e');
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
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached);
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
