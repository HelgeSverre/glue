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
  })  : _parameters = _parametersFromInputSchema(descriptor.inputSchema);

  final McpClient client;
  final String serverId;
  final String bareName;
  final McpToolDescriptor descriptor;
  final List<ToolParameter> _parameters;

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
/// Skips descriptors whose namespaced name conflicts with [reservedNames]
/// (typically the agent's native tools — natives win to avoid surprise
/// behaviour from a server claiming `read_file`).
List<McpTool> buildMcpTools({
  required McpClient client,
  required String serverId,
  required List<McpToolDescriptor> descriptors,
  Set<String> reservedNames = const {},
}) {
  return descriptors
      .where((d) => !reservedNames.contains(d.name))
      .map((d) => McpTool(
            client: client,
            serverId: serverId,
            bareName: d.name,
            descriptor: d,
          ))
      .toList();
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
    final prop =
        raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    return ToolParameter(
      name: paramName,
      type: (prop['type'] as String?) ?? 'string',
      description: (prop['description'] as String?) ?? '',
      required: required.contains(paramName),
      items: prop['items'] is Map
          ? (prop['items'] as Map).cast<String, dynamic>()
          : null,
    );
  }).toList();
}
