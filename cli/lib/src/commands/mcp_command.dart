/// Top-level `glue mcp …` subcommands.
///
/// CLI-side surface is intentionally light — without a running session
/// we can only inspect config + credentials, not live pool state. The
/// `/mcp …` slash commands (cli/lib/src/commands/slash/mcp.dart) mirror
/// these but show live pool state because they run inside the TUI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glue_harness/glue_harness.dart';

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
    addSubcommand(McpListCommand());
    addSubcommand(McpAuthCommand());
  }

  @override
  String get name => 'mcp';

  @override
  String get description => 'Manage Model Context Protocol (MCP) servers.';
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
      stdout.writeln(
          'Add a server under `mcp.servers:` in '
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
    stdout.writeln('Use `/mcp` inside a Glue session for live connection state.');
    return 0;
  }
}

// ─── auth subcommands ──────────────────────────────────────────────────────

class McpAuthCommand extends Command<int> {
  McpAuthCommand() {
    addSubcommand(McpAuthSetCommand());
  }

  @override
  String get name => 'auth';

  @override
  String get description => 'Manage credentials for MCP servers.';
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

// ─── helpers ───────────────────────────────────────────────────────────────

GlueConfig? _safeLoadConfig() {
  try {
    return GlueConfig.load(environment: Environment.detect());
  } on ConfigError catch (e) {
    stderr.writeln('Failed to load config: ${e.message}');
    return null;
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
