/// MCP (Model Context Protocol) configuration data models.
///
/// Config is loaded from (in precedence order):
///   1. Project-local `.glue/mcp.json`
///   2. Global `~/.glue/mcp.json`
///   3. `mcp:` section in `~/.glue/config.yaml`
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Auth models
// ---------------------------------------------------------------------------

/// How an MCP server authenticates incoming connections.
sealed class McpAuth {
  const McpAuth();
}

/// No authentication required (most stdio servers).
class McpNoAuth extends McpAuth {
  const McpNoAuth();
}

/// Static token / API key passed as an HTTP header.
class McpTokenAuth extends McpAuth {
  final String? envVar;
  final String? storedKey;
  final String headerName;
  final String headerPrefix;

  const McpTokenAuth({
    this.envVar,
    this.storedKey,
    this.headerName = 'Authorization',
    this.headerPrefix = 'Bearer',
  });
}

// ---------------------------------------------------------------------------
// Transport config models
// ---------------------------------------------------------------------------

/// Transport configuration for an MCP server.
sealed class McpTransportConfig {
  const McpTransportConfig();
}

/// Local process spawned via stdio.
class McpStdioConfig extends McpTransportConfig {
  final String command;
  final List<String> args;
  final Map<String, String> env;

  const McpStdioConfig({
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  /// Human-readable transport label.
  String get label => 'stdio';
}

/// Remote server via Server-Sent Events (legacy MCP transport).
class McpSseConfig extends McpTransportConfig {
  final Uri url;
  final Map<String, String> headers;

  const McpSseConfig({
    required this.url,
    this.headers = const {},
  });

  String get label => 'sse';
}

/// Remote server via streamable HTTP (modern MCP transport).
class McpStreamableHttpConfig extends McpTransportConfig {
  final Uri url;
  final Map<String, String> headers;

  const McpStreamableHttpConfig({
    required this.url,
    this.headers = const {},
  });

  String get label => 'http';
}

// ---------------------------------------------------------------------------
// Server config
// ---------------------------------------------------------------------------

/// Where the server config was sourced from.
enum McpServerSource { project, global, config, registry }

/// Configuration for a single MCP server.
class McpServerConfig {
  final String id;
  final String name;
  final McpTransportConfig transport;
  final McpAuth auth;
  final bool autoConnect;
  final bool enabled;
  final McpServerSource source;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.transport,
    this.auth = const McpNoAuth(),
    this.autoConnect = false,
    this.enabled = true,
    this.source = McpServerSource.config,
  });

  String get transportLabel => switch (transport) {
        McpStdioConfig() => 'stdio',
        McpSseConfig() => 'sse',
        McpStreamableHttpConfig() => 'http',
      };
}

// ---------------------------------------------------------------------------
// Top-level MCP config
// ---------------------------------------------------------------------------

/// Aggregated MCP configuration.
class McpConfig {
  final Map<String, McpServerConfig> servers;

  const McpConfig({
    this.servers = const {},
  });

  bool get isEmpty => servers.isEmpty;

  /// Load MCP configuration by merging multiple sources:
  ///   1. Project-local `.glue/mcp.json` (highest precedence)
  ///   2. Global `~/.glue/mcp.json`
  ///   3. `inline` map from `config.yaml` `mcp.servers:` (lowest precedence)
  ///
  /// Servers with the same id are overridden by higher-precedence sources.
  static McpConfig load({
    String? glueDir,
    String? cwd,
    Map<String, dynamic>? inlineSection,
    Map<String, String>? env,
  }) {
    final home = env?['HOME'] ?? Platform.environment['HOME'] ?? '.';
    final resolvedGlueDir = glueDir ?? '$home/.glue';
    final resolvedCwd = cwd ?? Directory.current.path;

    final merged = <String, McpServerConfig>{};

    // Lowest precedence: inline config.yaml section.
    if (inlineSection != null) {
      final inlineServers = _parseInlineSection(inlineSection);
      for (final entry in inlineServers.entries) {
        merged[entry.key] = entry.value;
      }
    }

    // Mid: global ~/.glue/mcp.json
    final globalJson = File(p.join(resolvedGlueDir, 'mcp.json'));
    if (globalJson.existsSync()) {
      final globalServers =
          _parseMcpJson(globalJson.readAsStringSync(), McpServerSource.global);
      for (final entry in globalServers.entries) {
        merged[entry.key] = entry.value;
      }
    }

    // High: project-local .glue/mcp.json
    final projectJson = File(p.join(resolvedCwd, '.glue', 'mcp.json'));
    if (projectJson.existsSync()) {
      final projectServers = _parseMcpJson(
          projectJson.readAsStringSync(), McpServerSource.project);
      for (final entry in projectServers.entries) {
        merged[entry.key] = entry.value;
      }
    }

    return McpConfig(servers: merged);
  }

  /// Parse an mcp.json file (Claude Code-compatible format).
  ///
  /// ```json
  /// {
  ///   "mcpServers": {
  ///     "filesystem": {
  ///       "command": "npx",
  ///       "args": ["-y", "@modelcontextprotocol/server-filesystem"],
  ///       "env": {}
  ///     }
  ///   }
  /// }
  /// ```
  static Map<String, McpServerConfig> _parseMcpJson(
      String jsonText, McpServerSource source) {
    final result = <String, McpServerConfig>{};
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return result;
      final servers = decoded['mcpServers'];
      if (servers is! Map) return result;
      for (final entry in servers.entries) {
        final id = entry.key.toString();
        final def = entry.value;
        if (def is! Map) continue;
        final config =
            _parseServerDef(id, Map<String, dynamic>.from(def), source: source);
        if (config != null) result[id] = config;
      }
    } on FormatException {
      // Silently ignore malformed JSON
    }
    return result;
  }

  /// Parse a config.yaml `mcp.servers:` inline section.
  static Map<String, McpServerConfig> _parseInlineSection(
      Map<String, dynamic> section) {
    final result = <String, McpServerConfig>{};
    final servers = section['servers'];
    if (servers is! Map) return result;
    for (final entry in servers.entries) {
      final id = entry.key.toString();
      final def = entry.value;
      if (def is! Map) continue;
      final config = _parseServerDef(id, Map<String, dynamic>.from(def),
          source: McpServerSource.config);
      if (config != null) result[id] = config;
    }
    return result;
  }

  static McpServerConfig? _parseServerDef(
    String id,
    Map<String, dynamic> def, {
    required McpServerSource source,
  }) {
    final name = def['name'] as String? ?? id;
    final enabled = def['enabled'] as bool? ?? true;
    final autoConnect =
        def['autoConnect'] as bool? ?? def['auto_connect'] as bool? ?? false;

    McpTransportConfig transport;

    // Stdio: has `command` field.
    final command = def['command'] as String?;
    if (command != null) {
      final argsList = def['args'];
      final args = argsList is List ? argsList.cast<String>() : <String>[];
      final envMap = def['env'];
      final env = envMap is Map
          ? Map<String, String>.fromEntries(envMap.entries
              .map((e) => MapEntry(e.key.toString(), e.value.toString())))
          : <String, String>{};
      transport = McpStdioConfig(command: command, args: args, env: env);
    } else {
      // HTTP/SSE: has `url` field.
      final rawUrl = def['url'] as String?;
      if (rawUrl == null) return null; // Neither stdio nor HTTP
      final url = Uri.tryParse(rawUrl);
      if (url == null) return null;

      final transportType = def['transport'] as String? ?? 'sse';
      if (transportType == 'streamable-http' || transportType == 'http') {
        transport = McpStreamableHttpConfig(url: url);
      } else {
        transport = McpSseConfig(url: url);
      }
    }

    // Auth.
    McpAuth auth = const McpNoAuth();
    final authDef = def['auth'];
    if (authDef is Map) {
      final authType = authDef['type'] as String? ?? 'token';
      if (authType == 'token' || authType == 'api_key') {
        auth = McpTokenAuth(
          envVar: authDef['env_var'] as String?,
          storedKey: authDef['key'] as String?,
          headerName: authDef['header_name'] as String? ?? 'Authorization',
          headerPrefix: authDef['header_prefix'] as String? ?? 'Bearer',
        );
      }
    }

    return McpServerConfig(
      id: id,
      name: name,
      transport: transport,
      auth: auth,
      autoConnect: autoConnect,
      enabled: enabled,
      source: source,
    );
  }
}
