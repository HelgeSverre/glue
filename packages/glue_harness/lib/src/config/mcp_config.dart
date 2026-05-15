/// Typed configuration for MCP (Model Context Protocol) servers.
///
/// Parsed from the `mcp:` section of `~/.glue/config.yaml`. Env-var
/// interpolation (`${VAR}`) happens at load — missing vars fail loudly
/// with the offending server name and var name, so users don't find out
/// at session start.
///
/// See `docs/plans/2026-04-29-mcp-client.md` for the wire-config shape.
library;

import 'package:glue_harness/src/config/glue_config.dart' show ConfigError;

/// Where the server lives and how to talk to it.
sealed class McpServerSpec {
  const McpServerSpec({
    required this.id,
    this.enabled = true,
    this.callTimeoutSeconds,
  });

  /// User-chosen local id (the YAML key). Used for namespacing tools
  /// (`<id>.<tool>`) and as the credential-store namespace.
  final String id;

  /// `false` parks the server without removing it from config.
  final bool enabled;

  /// Per-server override of [McpConfig.callTimeoutSeconds].
  final int? callTimeoutSeconds;
}

class McpStdioServerSpec extends McpServerSpec {
  const McpStdioServerSpec({
    required super.id,
    required this.command,
    this.args = const [],
    this.env = const {},
    this.workingDirectory,
    super.enabled,
    super.callTimeoutSeconds,
  });

  final String command;
  final List<String> args;

  /// Server-config env keys (after `${VAR}` expansion) added to the
  /// scrubbed child environment.
  final Map<String, String> env;

  final String? workingDirectory;
}

class McpHttpServerSpec extends McpServerSpec {
  const McpHttpServerSpec({
    required super.id,
    required this.url,
    this.auth = const McpNoAuth(),
    super.enabled,
    super.callTimeoutSeconds,
  });

  final Uri url;
  final McpAuthSpec auth;
}

class McpWebSocketServerSpec extends McpServerSpec {
  const McpWebSocketServerSpec({
    required super.id,
    required this.url,
    this.auth = const McpNoAuth(),
    super.enabled,
    super.callTimeoutSeconds,
  });

  final Uri url;
  final McpAuthSpec auth;
}

// ─── Auth ──────────────────────────────────────────────────────────────────

sealed class McpAuthSpec {
  const McpAuthSpec();
}

/// No auth header. Stdio servers default to this; HTTP servers can opt in.
class McpNoAuth extends McpAuthSpec {
  const McpNoAuth();
}

/// Bearer token. [token] is `null` when the value comes from the
/// credential store at session start (`mcp:<id>:bearer`). When non-null
/// it's the literal token (post env-var expansion).
class McpBearerAuth extends McpAuthSpec {
  const McpBearerAuth({this.token});
  final String? token;
}

/// OAuth 2.1 with PKCE + DCR. Credentials live in the credential store
/// under `mcp:<id>:oauth.*` — config carries no secrets.
class McpOAuthAuth extends McpAuthSpec {
  const McpOAuthAuth();
}

// ─── Tool policy ───────────────────────────────────────────────────────────

class McpToolPolicy {
  const McpToolPolicy({
    this.autoApprove = const [],
    this.deny = const [],
  });

  /// Namespaced names or glob patterns (`*.read_file`).
  final List<String> autoApprove;

  /// Namespaced names or glob patterns (`*.delete_file`).
  final List<String> deny;

  /// Returns `true` if [namespacedName] matches any [autoApprove] pattern.
  bool isAutoApproved(String namespacedName) =>
      autoApprove.any((p) => _globMatch(p, namespacedName));

  /// Returns `true` if [namespacedName] matches any [deny] pattern.
  bool isDenied(String namespacedName) =>
      deny.any((p) => _globMatch(p, namespacedName));
}

// ─── Reconnect policy ──────────────────────────────────────────────────────

class McpReconnectPolicy {
  const McpReconnectPolicy({
    this.enabled = true,
    this.initialDelayMs = 500,
    this.maxDelayMs = 30000,
    this.maxAttempts = 10,
  });

  final bool enabled;
  final int initialDelayMs;
  final int maxDelayMs;
  final int maxAttempts;
}

// ─── Top-level config ──────────────────────────────────────────────────────

class McpConfig {
  const McpConfig({
    this.servers = const [],
    this.toolPolicy = const McpToolPolicy(),
    this.reconnect = const McpReconnectPolicy(),
    this.callTimeoutSeconds = 30,
    this.subprocessEnv = McpSubprocessEnvMode.allowlist,
  });

  /// All configured servers, in YAML order.
  final List<McpServerSpec> servers;

  final McpToolPolicy toolPolicy;
  final McpReconnectPolicy reconnect;

  /// Default per-call timeout. May be overridden per server.
  final int callTimeoutSeconds;

  /// `allowlist` (default) scrubs the parent env for stdio subprocesses;
  /// `full` inherits everything (matches Claude Desktop's behaviour).
  final McpSubprocessEnvMode subprocessEnv;

  bool get hasAnyServer => servers.isNotEmpty;
}

enum McpSubprocessEnvMode { allowlist, full }

// ─── Parser ────────────────────────────────────────────────────────────────

/// Parses the `mcp:` section of a YAML config map. Returns the default
/// (empty) [McpConfig] when [section] is null.
///
/// Throws [ConfigError] for malformed shapes or unresolved `${VAR}`
/// interpolations. The error message names the offending server and key
/// so the user can fix it without digging.
McpConfig parseMcpConfig(Object? section, Map<String, String> env) {
  if (section == null) return const McpConfig();
  if (section is! Map) {
    throw ConfigError(
      '`mcp:` must be a mapping, got ${section.runtimeType}.',
    );
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

  final toolPolicy = _parseToolPolicy(root['tool_policy']);
  final reconnect = _parseReconnect(root['reconnect']);
  final callTimeoutSeconds = (root['call_timeout_seconds'] as int?) ?? 30;
  final subprocessEnv = _parseEnvMode(root['subprocess_env']);

  return McpConfig(
    servers: servers,
    toolPolicy: toolPolicy,
    reconnect: reconnect,
    callTimeoutSeconds: callTimeoutSeconds,
    subprocessEnv: subprocessEnv,
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
        envBlock[key] =
            _expandEnvVars(value, env, server: id, field: 'env.$key');
      }
    }
    return McpStdioServerSpec(
      id: id,
      command: _expandEnvVars(command, env, server: id, field: 'command'),
      args: args
          .map((a) => _expandEnvVars(a, env, server: id, field: 'args'))
          .toList(),
      env: envBlock,
      workingDirectory: raw['working_directory'] as String?,
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
          '`mcp.servers.$id.url` is not a valid URI: "$expandedUrl".');
    }
    final isWebSocket = parsed.scheme == 'ws' || parsed.scheme == 'wss';
    if (isWebSocket) {
      return McpWebSocketServerSpec(
        id: id,
        url: parsed,
        auth: auth,
        enabled: enabled,
        callTimeoutSeconds: callTimeout,
      );
    }
    return McpHttpServerSpec(
      id: id,
      url: parsed,
      auth: auth,
      enabled: enabled,
      callTimeoutSeconds: callTimeout,
    );
  }

  throw ConfigError(
    '`mcp.servers.$id` must set either `command` (stdio) or `url` (HTTP/WS).',
  );
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
  final auto =
      (raw['auto_approve'] as List?)?.cast<String>() ?? const <String>[];
  final deny = (raw['deny'] as List?)?.cast<String>() ?? const <String>[];
  return McpToolPolicy(autoApprove: auto, deny: deny);
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

/// Expands `${VAR}` references in [input] against [env]. Empty strings
/// are treated as missing (matches the design doc's intent — if you
/// `unset VAR` the resolution should be the same as never setting it).
///
/// Unresolved vars fail loudly with the server id + field name so users
/// don't discover the problem at session start.
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

// ─── glob matcher ──────────────────────────────────────────────────────────

/// Minimal glob matcher: `*` matches any sequence (including empty),
/// `?` matches one character. Used for `tool_policy.auto_approve` /
/// `deny` patterns.
bool _globMatch(String pattern, String value) {
  // Quick paths.
  if (pattern == value) return true;
  if (pattern == '*') return true;

  // Convert glob to RegExp.
  final buf = StringBuffer('^');
  for (final ch in pattern.runes) {
    final c = String.fromCharCode(ch);
    switch (c) {
      case '*':
        buf.write('.*');
      case '?':
        buf.write('.');
      // RegExp metacharacters that need escaping.
      case '.':
      case '\\':
      case '+':
      case '(':
      case ')':
      case '[':
      case ']':
      case '{':
      case '}':
      case '^':
      case r'$':
      case '|':
        buf.write('\\$c');
      default:
        buf.write(c);
    }
  }
  buf.write(r'$');
  return RegExp(buf.toString()).hasMatch(value);
}
