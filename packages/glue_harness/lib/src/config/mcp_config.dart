/// YAML→config parser for MCP servers.
///
/// The typed config classes themselves live in
/// `glue_strategies/src/mcp_client/config.dart` so the pool (in
/// strategies) can consume them without crossing the layer boundary.
/// This file is the harness-side adapter: YAML + ConfigError +
/// env-var expansion.
library;

import 'package:glue_harness/src/config/glue_config.dart' show ConfigError;
import 'package:glue_strategies/glue_strategies.dart';

export 'package:glue_strategies/glue_strategies.dart'
    show
        McpAuthSpec,
        McpBearerAuth,
        McpConfig,
        McpNoAuth,
        McpOAuthAuth,
        McpReconnectPolicy,
        McpServerSpec,
        McpStdioServerSpec,
        McpToolPolicy,
        McpUrlServerSpec,
        McpSubprocessEnvMode;

/// Parses the `mcp:` section of a YAML config map. Returns the default
/// (empty) [McpConfig] when [section] is null.
///
/// Throws [ConfigError] for malformed shapes or unresolved `${VAR}`
/// interpolations. The error message names the offending server and key.
McpConfig parseMcpConfig(Object? section, Map<String, String> env) {
  if (section == null) return const McpConfig();
  if (section is! Map) {
    throw ConfigError('`mcp:` must be a mapping, got ${section.runtimeType}.');
  }
  final root = section.cast<dynamic, dynamic>();

  final servers = <McpServerSpec>[];
  final rawServers = root['servers'];
  if (rawServers != null) {
    if (rawServers is! Map) {
      throw ConfigError('`mcp.servers` must be a mapping.');
    }
    for (final entry in rawServers.entries) {
      final id = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) {
        throw ConfigError(
          '`mcp.servers.$id` must be a mapping, got ${raw.runtimeType}.',
        );
      }
      servers.add(_parseServer(id, raw.cast<dynamic, dynamic>(), env));
    }
  }

  return McpConfig(
    servers: servers,
    toolPolicy: _parseToolPolicy(root['tool_policy']),
    reconnect: _parseReconnect(root['reconnect']),
    callTimeoutSeconds: (root['call_timeout_seconds'] as int?) ?? 30,
    subprocessEnv: _parseEnvMode(root['subprocess_env']),
  );
}

McpServerSpec _parseServer(
  String id,
  Map<dynamic, dynamic> raw,
  Map<String, String> env,
) {
  final enabled = raw['enabled'] as bool? ?? true;
  final callTimeout = raw['call_timeout_seconds'] as int?;
  final command = raw['command'] as String?;
  final url = raw['url'] as String?;

  if (command != null && url != null) {
    throw ConfigError(
      '`mcp.servers.$id` cannot set both `command` and `url` — pick one.',
    );
  }

  if (command != null) {
    final args = (raw['args'] as List?)?.cast<String>() ?? const <String>[];
    final envBlock = <String, String>{};
    final rawEnv = raw['env'];
    if (rawEnv is Map) {
      for (final e in rawEnv.entries) {
        final key = e.key.toString();
        final value = e.value?.toString();
        if (value == null) continue;
        envBlock[key] = _expandEnvVars(
          value,
          env,
          server: id,
          field: 'env.$key',
        );
      }
    }
    return McpStdioServerSpec(
      id: id,
      command: _expandEnvVars(command, env, server: id, field: 'command'),
      args: args
          .map((a) => _expandEnvVars(a, env, server: id, field: 'args'))
          .toList(),
      env: envBlock,
      workingDirectory: raw['working_directory'] != null
          ? expandUserPath(
              _expandEnvVars(
                raw['working_directory'] as String,
                env,
                server: id,
                field: 'working_directory',
              ),
              home: env['HOME'] ?? env['USERPROFILE'],
            )
          : null,
      enabled: enabled,
      callTimeoutSeconds: callTimeout,
    );
  }

  if (url != null) {
    final expandedUrl = _expandEnvVars(url, env, server: id, field: 'url');
    final auth = _parseAuth(raw['auth'], env, serverId: id);
    final parsed = Uri.tryParse(expandedUrl);
    if (parsed == null) {
      throw ConfigError(
        '`mcp.servers.$id.url` is not a valid URI: "$expandedUrl".',
      );
    }
    final isWebSocket = parsed.scheme == 'ws' || parsed.scheme == 'wss';
    return McpUrlServerSpec(
      id: id,
      url: parsed,
      isWebSocket: isWebSocket,
      auth: auth,
      enabled: enabled,
      callTimeoutSeconds: callTimeout,
      resourceMetadataUrl: _optionalUri(raw['resource_metadata_url']),
      authorizationServer: _optionalUri(raw['authorization_server']),
    );
  }

  throw ConfigError(
    '`mcp.servers.$id` must set either `command` (stdio) or `url` (HTTP/WS).',
  );
}

Uri? _optionalUri(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return Uri.tryParse(raw);
}

McpAuthSpec _parseAuth(
  Object? raw,
  Map<String, String> env, {
  required String serverId,
}) {
  if (raw == null) return const McpNoAuth();
  if (raw is! Map) {
    throw ConfigError('`mcp.servers.$serverId.auth` must be a mapping.');
  }
  final kind = raw['kind'] as String?;
  switch (kind) {
    case 'bearer':
      final rawToken = raw['token'] as String?;
      final token = rawToken != null
          ? _expandEnvVars(rawToken, env, server: serverId, field: 'auth.token')
          : null;
      return McpBearerAuth(token: token);
    case 'oauth':
      return const McpOAuthAuth();
    case 'none':
    case null:
      return const McpNoAuth();
    default:
      throw ConfigError(
        '`mcp.servers.$serverId.auth.kind` must be one of: bearer, oauth, '
        'none (got "$kind").',
      );
  }
}

McpToolPolicy _parseToolPolicy(Object? raw) {
  if (raw == null) return const McpToolPolicy();
  if (raw is! Map) {
    throw ConfigError('`mcp.tool_policy` must be a mapping.');
  }
  return McpToolPolicy(
    autoApprove:
        (raw['auto_approve'] as List?)?.cast<String>() ?? const <String>[],
    deny: (raw['deny'] as List?)?.cast<String>() ?? const <String>[],
  );
}

McpReconnectPolicy _parseReconnect(Object? raw) {
  if (raw == null) return const McpReconnectPolicy();
  if (raw is! Map) {
    throw ConfigError('`mcp.reconnect` must be a mapping.');
  }
  return McpReconnectPolicy(
    enabled: raw['enabled'] as bool? ?? true,
    initialDelayMs: raw['initial_delay_ms'] as int? ?? 500,
    maxDelayMs: raw['max_delay_ms'] as int? ?? 30000,
    maxAttempts: raw['max_attempts'] as int? ?? 10,
  );
}

McpSubprocessEnvMode _parseEnvMode(Object? raw) {
  if (raw == null) return McpSubprocessEnvMode.allowlist;
  final s = raw.toString();
  return switch (s) {
    'allowlist' => McpSubprocessEnvMode.allowlist,
    'full' => McpSubprocessEnvMode.full,
    _ => throw ConfigError(
      '`mcp.subprocess_env` must be "allowlist" or "full" (got "$s").',
    ),
  };
}

// ─── env-var expansion ─────────────────────────────────────────────────────

final _envVarPattern = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');

String _expandEnvVars(
  String input,
  Map<String, String> env, {
  required String server,
  required String field,
}) {
  return input.replaceAllMapped(_envVarPattern, (m) {
    final name = m.group(1)!;
    final value = env[name];
    if (value == null || value.isEmpty) {
      throw ConfigError(
        '`mcp.servers.$server.$field` references \${$name} but the env var '
        'is unset or empty.',
      );
    }
    return value;
  });
}
