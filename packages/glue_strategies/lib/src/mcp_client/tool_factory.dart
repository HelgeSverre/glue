/// Wraps MCP tool descriptors as glue_core [Tool] implementations.
///
/// The agent loop sees an MCP-sourced tool as a normal [Tool]; the
/// permission gate, render path, session log, and observability all
/// behave the same. The only difference is the namespaced name
/// (`<serverId>.<toolName>`) and that `execute()` delegates to
/// [McpClient.callTool].
library;

import 'package:glue_core/glue_core.dart';

import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/protocol.dart';

/// Wraps a single MCP tool descriptor.
///
/// [bareName] is the server-side tool name (sent to `tools/call`).
/// [name] is the namespaced surface (`<serverId>__<bareName>`) — that's
/// what shows up in autocomplete, permission prompts, and the agent's
/// tool registry.
///
/// Why double-underscore: OpenAI's function-name validator only allows
/// `^[a-zA-Z0-9_-]+$` (no dots). Single `_` collides with tool-name
/// snake_case and single `-` collides with hyphenated server ids
/// (`my-mcp-server`). `__` is rare in both, so the boundary stays
/// unambiguous and the name remains visually parseable.
class McpTool extends Tool {
  McpTool({
    required this.client,
    required this.serverId,
    required this.bareName,
    required this.descriptor,
    this.onAuthFailure,
  }) : _parameters = _parametersFromInputSchema(descriptor.inputSchema);

  final McpClient client;
  final String serverId;
  final String bareName;
  final McpToolDescriptor descriptor;
  final List<ToolParameter> _parameters;

  /// Invoked when a `tools/call` fails with `auth_expired` (a mid-session
  /// 401). Lets the pool re-trigger the auth flow — the failing call still
  /// returns a failed [ToolResult] to the agent (M2).
  final void Function(McpCallFailure failure)? onAuthFailure;

  @override
  String get name => '${serverId}__$bareName';

  @override
  String get description => descriptor.description;

  @override
  List<ToolParameter> get parameters => _parameters;

  /// MCP tools can do anything (read, write, exec, network). We default
  /// to the most-trusted bucket so the permission gate asks unless the
  /// user has explicitly auto-approved via `mcp.tool_policy.auto_approve`.
  @override
  ToolTrust get trust => ToolTrust.command;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    try {
      final result = await client.callTool(bareName, args);
      return ToolResult(
        success: !result.isError,
        content: result.textPayload,
        metadata: {
          'mcp.server_id': serverId,
          'mcp.tool': bareName,
          if (result.isError) 'mcp.is_error': true,
        },
      );
    } on McpCallFailure catch (e) {
      // Surface a mid-session auth failure to the pool so it can re-auth /
      // emit the auth-required event (M2). This call still fails.
      if (e.reason == 'auth_expired') {
        onAuthFailure?.call(e);
      }
      return ToolResult(
        success: false,
        content: e.message ?? 'MCP call failed: ${e.reason}',
        metadata: {
          'mcp.server_id': serverId,
          'mcp.tool': bareName,
          'mcp.failure_reason': e.reason,
          if (e.code != null) 'mcp.error_code': e.code,
          'retryable': e.retryable,
        },
      );
    }
  }
}

/// Builds glue_core [Tool]s for every descriptor advertised by a server.
///
/// MCP tools are always registered under their namespaced name
/// (`<serverId>__<tool>`), so they never actually shadow a native tool.
/// The [reservedNames] filter therefore compares the *namespaced* name —
/// dropping a tool only when it would genuinely collide, instead of
/// silently discarding any MCP tool whose bare name matches a native like
/// `read_file` or `grep` (L13). Descriptors that can't be converted are
/// skipped individually rather than failing the whole connection (L12).
List<McpTool> buildMcpTools({
  required McpClient client,
  required String serverId,
  required List<McpToolDescriptor> descriptors,
  Set<String> reservedNames = const {},
  void Function(McpCallFailure failure)? onAuthFailure,
}) {
  final tools = <McpTool>[];
  for (final d in descriptors) {
    if (reservedNames.contains('${serverId}__${d.name}')) continue;
    try {
      tools.add(
        McpTool(
          client: client,
          serverId: serverId,
          bareName: d.name,
          descriptor: d,
          onAuthFailure: onAuthFailure,
        ),
      );
    } catch (_) {
      // Skip a descriptor whose schema we can't convert.
    }
  }
  return tools;
}

// ─── inputSchema → ToolParameter[] ─────────────────────────────────────────

List<ToolParameter> _parametersFromInputSchema(Map<String, dynamic> schema) {
  final required = ((schema['required'] as List?) ?? const <Object?>[])
      .map((e) => e.toString())
      .toSet();
  final properties = schema['properties'];
  if (properties is! Map) return const [];

  return properties.entries.map((entry) {
    final paramName = entry.key.toString();
    final raw = entry.value;
    final prop = raw is Map
        ? raw.cast<String, dynamic>()
        : const <String, dynamic>{};
    return ToolParameter(
      name: paramName,
      type: _schemaType(prop['type']),
      description: (prop['description'] as String?) ?? '',
      required: required.contains(paramName),
      items: prop['items'] is Map
          ? (prop['items'] as Map).cast<String, dynamic>()
          : null,
    );
  }).toList();
}

/// Resolves a JSON-Schema `type` value to a single type string. JSON
/// Schema permits a list (`["string","null"]` for nullable fields); we
/// take the first non-`null` entry. Anything unrecognised falls back to
/// `string` (L12).
String _schemaType(Object? raw) {
  if (raw is String) return raw;
  if (raw is List) {
    return raw.whereType<String>().firstWhere(
      (t) => t != 'null',
      orElse: () => 'string',
    );
  }
  return 'string';
}
