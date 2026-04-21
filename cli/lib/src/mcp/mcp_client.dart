/// MCP protocol client: wraps a transport with MCP handshake and tool calls.
library;

import 'dart:async';

import 'package:glue/src/mcp/mcp_transport.dart';

// ---------------------------------------------------------------------------
// MCP data models
// ---------------------------------------------------------------------------

/// Capabilities advertised by an MCP server after initialization.
class McpServerCapabilities {
  final bool hasTools;
  final bool hasResources;
  final bool hasPrompts;
  final bool toolListChangedSupported;

  const McpServerCapabilities({
    this.hasTools = false,
    this.hasResources = false,
    this.hasPrompts = false,
    this.toolListChangedSupported = false,
  });

  factory McpServerCapabilities.fromJson(Map<String, dynamic> json) {
    final caps = json['capabilities'];
    if (caps is! Map) {
      return const McpServerCapabilities();
    }
    final toolsCap = caps['tools'];
    return McpServerCapabilities(
      hasTools: toolsCap != null,
      hasResources: caps['resources'] != null,
      hasPrompts: caps['prompts'] != null,
      toolListChangedSupported:
          toolsCap is Map && toolsCap['listChanged'] == true,
    );
  }
}

/// Definition of a tool provided by an MCP server.
class McpToolDef {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  const McpToolDef({
    required this.name,
    this.description,
    required this.inputSchema,
  });

  factory McpToolDef.fromJson(Map<String, dynamic> json) {
    final schema = json['inputSchema'];
    return McpToolDef(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: schema is Map ? Map<String, dynamic>.from(schema) : {},
    );
  }
}

/// Content item in a tool result.
class McpContent {
  final String type;
  final String? text;
  final String? mimeType;
  final String? data;

  const McpContent({
    required this.type,
    this.text,
    this.mimeType,
    this.data,
  });

  factory McpContent.fromJson(Map<String, dynamic> json) {
    return McpContent(
      type: json['type'] as String? ?? 'text',
      text: json['text'] as String?,
      mimeType: json['mimeType'] as String?,
      data: json['data'] as String?,
    );
  }
}

/// Result of calling a tool on an MCP server.
class McpToolResult {
  final List<McpContent> content;
  final bool isError;

  const McpToolResult({
    required this.content,
    this.isError = false,
  });

  factory McpToolResult.fromJson(Map<String, dynamic> json) {
    final contentList = json['content'];
    final items = <McpContent>[];
    if (contentList is List) {
      for (final item in contentList) {
        if (item is Map) {
          items.add(McpContent.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return McpToolResult(
      content: items,
      isError: json['isError'] as bool? ?? false,
    );
  }

  /// All text content joined with newlines.
  String get textContent {
    final parts = content.where((c) => c.type == 'text' && c.text != null);
    if (parts.isEmpty) return '';
    return parts.map((c) => c.text!).join('\n');
  }
}

// ---------------------------------------------------------------------------
// MCP client
// ---------------------------------------------------------------------------

/// High-level MCP client. Wraps a [McpTransport] and handles the protocol
/// lifecycle: `initialize` handshake, `tools/list`, `tools/call`, shutdown.
class McpClient {
  final McpTransport transport;

  McpServerCapabilities? _capabilities;
  String? _serverName;
  String? _serverVersion;

  McpClient(this.transport);

  McpServerCapabilities? get capabilities => _capabilities;
  String? get serverName => _serverName;
  String? get serverVersion => _serverVersion;

  /// Perform the MCP initialize handshake.
  ///
  /// Must be called before [listTools] or [callTool].
  Future<void> initialize() async {
    final result = await transport.request('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {
        'roots': {'listChanged': true},
      },
      'clientInfo': {
        'name': 'glue',
        'version': '0.1.1',
      },
    });
    _capabilities = McpServerCapabilities.fromJson(result);
    final serverInfo = result['serverInfo'];
    if (serverInfo is Map) {
      _serverName = serverInfo['name'] as String?;
      _serverVersion = serverInfo['version'] as String?;
    }
    await transport.notify('notifications/initialized', null);
  }

  /// Discover all tools advertised by the server.
  Future<List<McpToolDef>> listTools() async {
    final result = await transport.request('tools/list', null);
    final toolsList = result['tools'];
    if (toolsList is! List) return const [];
    return toolsList
        .whereType<Map<String, dynamic>>()
        .map(McpToolDef.fromJson)
        .toList();
  }

  /// Call a tool on the server and return its result.
  Future<McpToolResult> callTool(
      String name, Map<String, dynamic> arguments) async {
    final result = await transport.request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return McpToolResult.fromJson(result);
  }

  /// Gracefully shut down the connection.
  Future<void> shutdown() async {
    try {
      await transport.request('shutdown', null);
      await transport.notify('exit', null);
    } catch (_) {
      // Best-effort; server may have already disconnected.
    } finally {
      await transport.close();
    }
  }

  /// Server-initiated notifications (e.g. `notifications/tools/list_changed`).
  Stream<McpNotification> get notifications => transport.notifications;
}
