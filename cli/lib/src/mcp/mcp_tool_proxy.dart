/// MCP Tool Proxy: bridges MCP server tools into Glue's Tool interface.
library;

import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/mcp/mcp_client.dart';

/// Adapts a single MCP tool definition as a Glue [Tool].
///
/// The tool name is namespaced as `{serverId}__{toolName}` to prevent
/// collisions between servers and with built-in tools. The LLM sees the
/// full namespaced name.
class McpToolProxy extends Tool {
  final String serverId;
  final McpToolDef def;
  final McpClient client;

  McpToolProxy({
    required this.serverId,
    required this.def,
    required this.client,
  });

  @override
  String get name => '${serverId}__${def.name}';

  @override
  String get description => def.description ?? 'MCP tool from $serverId';

  @override
  List<ToolParameter> get parameters => _extractParameters(def.inputSchema);

  @override
  ToolTrust get trust => ToolTrust.command;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    try {
      final result = await client.callTool(def.name, args);
      final text = result.textContent;
      return ToolResult(
        content: text.isNotEmpty ? text : '(no output)',
        success: !result.isError,
        summary: 'MCP: ${def.name} via $serverId',
        metadata: {
          'mcp_server': serverId,
          'mcp_tool': def.name,
        },
      );
    } catch (e) {
      return ToolResult(
        success: false,
        content: 'MCP tool error ($serverId/${def.name}): $e',
        metadata: {
          'mcp_server': serverId,
          'mcp_tool': def.name,
        },
      );
    }
  }

  /// Convert a JSON Schema `properties` object into [ToolParameter] list.
  static List<ToolParameter> _extractParameters(
      Map<String, dynamic> inputSchema) {
    final properties = inputSchema['properties'];
    if (properties is! Map) return const [];

    final required = inputSchema['required'];
    final requiredSet =
        required is List ? required.cast<String>().toSet() : <String>{};

    return properties.entries.map((entry) {
      final name = entry.key as String;
      final def = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : <String, dynamic>{};

      final type = def['type'] as String? ?? 'string';
      final description = def['description'] as String? ?? name;

      // JSON Schema array items.
      final itemsDef = def['items'];
      final items =
          itemsDef is Map ? Map<String, dynamic>.from(itemsDef) : null;

      return ToolParameter(
        name: name,
        type: type,
        description: description,
        required: requiredSet.contains(name),
        items: items,
      );
    }).toList();
  }
}
