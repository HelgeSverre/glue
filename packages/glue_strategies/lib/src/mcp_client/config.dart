/// Typed configuration types for MCP servers.
///
/// Pure data — no I/O, no parsing. The YAML→config parser lives in
/// `glue_harness/src/config/mcp_config.dart` (which can depend on these
/// types) so the layered architecture stays clean: strategies don't
/// import from harness.
///
/// See `docs/plans/2026-04-29-mcp-client.md` for the wire-config shape.
@MappableLib()
library;

import 'package:dart_mappable/dart_mappable.dart';
import 'package:glue_strategies/src/custom_mappers.dart';

part 'config.mapper.dart';

// ─── Server spec ─────────────────────────────────────────────────────────────

/// Where the server lives and how to talk to it.
@MappableClass(discriminatorKey: 'type')
sealed class McpServerSpec with McpServerSpecMappable {
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

@MappableClass(discriminatorValue: 'stdio')
class McpStdioServerSpec extends McpServerSpec with McpStdioServerSpecMappable {
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

@MappableClass(discriminatorValue: 'url', includeCustomMappers: [UriMapper()])
class McpUrlServerSpec extends McpServerSpec with McpUrlServerSpecMappable {
  const McpUrlServerSpec({
    required super.id,
    required this.url,
    required this.isWebSocket,
    this.auth = const McpNoAuth(),
    this.resourceMetadataUrl,
    this.authorizationServer,
    super.enabled,
    super.callTimeoutSeconds,
  });

  final Uri url;
  final bool isWebSocket;
  final McpAuthSpec auth;

  /// Cached RFC 9728 resource-metadata URL discovered on a prior
  /// session. Skips one HTTP round-trip at startup. Self-healing —
  /// stale value just falls back to fresh discovery.
  final Uri? resourceMetadataUrl;

  /// Cached authorization server URL discovered on a prior session.
  final Uri? authorizationServer;
}

// ─── Auth ──────────────────────────────────────────────────────────────────

@MappableClass(discriminatorKey: 'kind')
sealed class McpAuthSpec with McpAuthSpecMappable {
  const McpAuthSpec();
}

/// No auth header. Stdio servers default to this; HTTP servers can opt in.
@MappableClass(discriminatorValue: 'none')
class McpNoAuth extends McpAuthSpec with McpNoAuthMappable {
  const McpNoAuth();
}

/// Bearer token. [token] is `null` when the value comes from the
/// credential store at session start (`mcp:<id>:bearer`). When non-null
/// it's the literal token (post env-var expansion).
@MappableClass(discriminatorValue: 'bearer')
class McpBearerAuth extends McpAuthSpec with McpBearerAuthMappable {
  const McpBearerAuth({this.token});
  final String? token;
}

/// OAuth 2.1 with PKCE + DCR. Credentials live in the credential store
/// under `mcp:<id>:oauth.*` — config carries no secrets.
@MappableClass(discriminatorValue: 'oauth')
class McpOAuthAuth extends McpAuthSpec with McpOAuthAuthMappable {
  const McpOAuthAuth();
}

// ─── Tool policy ───────────────────────────────────────────────────────────

@MappableClass()
class McpToolPolicy with McpToolPolicyMappable {
  const McpToolPolicy({this.autoApprove = const [], this.deny = const []});

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

@MappableClass()
class McpReconnectPolicy with McpReconnectPolicyMappable {
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

@MappableClass()
class McpConfig with McpConfigMappable {
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

@MappableEnum(mode: ValuesMode.named)
enum McpSubprocessEnvMode { allowlist, full }

// ─── glob matcher ──────────────────────────────────────────────────────────

/// Minimal glob matcher: `*` matches any sequence (including empty),
/// `?` matches one character. Used for [McpToolPolicy] patterns.
bool _globMatch(String pattern, String value) {
  if (pattern == value) return true;
  if (pattern == '*') return true;

  final buf = StringBuffer('^');
  for (final ch in pattern.runes) {
    final c = String.fromCharCode(ch);
    switch (c) {
      case '*':
        buf.write('.*');
      case '?':
        buf.write('.');
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
