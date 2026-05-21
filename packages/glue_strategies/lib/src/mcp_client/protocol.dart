/// MCP wire-protocol message types (Model Context Protocol).
///
/// MCP is layered on JSON-RPC 2.0. We reuse `glue_server`'s
/// [JsonRpcMessage]/[JsonRpcTransport] for framing and add MCP-specific
/// param/result shapes here.
///
/// Pure data — no I/O. See `client.dart` for the dispatch logic and
/// `transport/stdio.dart` for the subprocess transport.
library;

/// Protocol version this client pins to. Updated per release.
const mcpProtocolVersion = '2025-03-26';

/// Minimum protocol version the client will accept from a server.
/// Older servers are refused with `protocol_too_old`.
const mcpMinimumProtocolVersion = '2024-11-05';

// ─── initialize ────────────────────────────────────────────────────────────

class McpClientInfo {
  const McpClientInfo({required this.name, required this.version});

  final String name;
  final String version;

  Map<String, dynamic> toJson() => {'name': name, 'version': version};
}

class McpServerInfo {
  const McpServerInfo({required this.name, required this.version});

  final String name;
  final String version;

  factory McpServerInfo.fromJson(Map<String, dynamic> json) => McpServerInfo(
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
  );
}

class McpClientCapabilities {
  const McpClientCapabilities({this.roots});

  /// We advertise `roots` so servers (e.g. filesystem) can scope access.
  final McpRootsCapability? roots;

  Map<String, dynamic> toJson() => {
    if (roots != null) 'roots': roots!.toJson(),
  };
}

class McpRootsCapability {
  const McpRootsCapability({this.listChanged = false});
  final bool listChanged;
  Map<String, dynamic> toJson() => {'listChanged': listChanged};
}

class McpServerCapabilities {
  const McpServerCapabilities({
    this.tools,
    this.prompts,
    this.resources,
    this.sampling,
    this.logging,
    this.experimental,
  });

  final McpToolsCapability? tools;
  final Map<String, dynamic>? prompts;
  final Map<String, dynamic>? resources;
  final Map<String, dynamic>? sampling;
  final Map<String, dynamic>? logging;
  final Map<String, dynamic>? experimental;

  factory McpServerCapabilities.fromJson(Map<String, dynamic> json) {
    final rawTools = json['tools'];
    return McpServerCapabilities(
      tools: rawTools is Map<String, dynamic>
          ? McpToolsCapability.fromJson(rawTools)
          : null,
      prompts: _mapOrNull(json['prompts']),
      resources: _mapOrNull(json['resources']),
      sampling: _mapOrNull(json['sampling']),
      logging: _mapOrNull(json['logging']),
      experimental: _mapOrNull(json['experimental']),
    );
  }

  bool get supportsSampling => sampling != null;
}

class McpToolsCapability {
  const McpToolsCapability({this.listChanged = false});
  final bool listChanged;
  factory McpToolsCapability.fromJson(Map<String, dynamic> json) =>
      McpToolsCapability(listChanged: json['listChanged'] as bool? ?? false);
}

class McpInitializeResult {
  const McpInitializeResult({
    required this.protocolVersion,
    required this.serverInfo,
    required this.capabilities,
    this.instructions,
  });

  final String protocolVersion;
  final McpServerInfo serverInfo;
  final McpServerCapabilities capabilities;
  final String? instructions;

  factory McpInitializeResult.fromJson(Map<String, dynamic> json) {
    return McpInitializeResult(
      protocolVersion: json['protocolVersion'] as String? ?? '',
      serverInfo: McpServerInfo.fromJson(
        (json['serverInfo'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      capabilities: McpServerCapabilities.fromJson(
        (json['capabilities'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      instructions: json['instructions'] as String?,
    );
  }
}

// ─── tools/list ────────────────────────────────────────────────────────────

class McpToolDescriptor {
  const McpToolDescriptor({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  factory McpToolDescriptor.fromJson(Map<String, dynamic> json) {
    return McpToolDescriptor(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      inputSchema:
          (json['inputSchema'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{'type': 'object'},
    );
  }
}

// ─── tools/call ────────────────────────────────────────────────────────────

/// One content item in a tool call result. MCP supports text, image, and
/// embedded resource variants; we model only `text` directly and pass
/// other kinds through as opaque maps so the agent loop can ignore them.
sealed class McpContent {
  const McpContent();

  factory McpContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'text') return McpTextContent(json['text'] as String? ?? '');
    return McpOpaqueContent(type ?? 'unknown', json);
  }
}

class McpTextContent extends McpContent {
  const McpTextContent(this.text);
  final String text;
}

class McpOpaqueContent extends McpContent {
  const McpOpaqueContent(this.type, this.raw);
  final String type;
  final Map<String, dynamic> raw;
}

class McpToolCallResult {
  const McpToolCallResult({required this.content, this.isError = false});

  final List<McpContent> content;
  final bool isError;

  factory McpToolCallResult.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    final items = rawContent is List
        ? rawContent
              .whereType<Map<String, dynamic>>()
              .map(McpContent.fromJson)
              .toList()
        : <McpContent>[];
    return McpToolCallResult(
      content: items,
      isError: json['isError'] as bool? ?? false,
    );
  }

  /// Concatenates all text content into a single string. Non-text items
  /// are summarised as `[<type>]`. Used to build the LLM-facing payload.
  String get textPayload {
    final parts = content.map<String>((c) {
      if (c is McpTextContent) return c.text;
      if (c is McpOpaqueContent) return '[${c.type}]';
      throw StateError('unreachable');
    });
    return parts.join('\n');
  }
}

// ─── error codes (Glue-reserved range) ─────────────────────────────────────

/// MCP-specific JSON-RPC error codes. The standard JSON-RPC codes
/// (-32700..-32603) come from [JsonRpcErrorCode] in glue_server.
abstract final class McpErrorCode {
  /// Glue-reserved: the server is rate-limited. Honour `Retry-After` /
  /// `data.retry_after_seconds` and retry once.
  static const int rateLimited = -32011;
}

// ─── method names ──────────────────────────────────────────────────────────

abstract final class McpMethod {
  static const initialize = 'initialize';
  static const initialized = 'notifications/initialized';
  static const toolsList = 'tools/list';
  static const toolsCall = 'tools/call';
  static const toolsListChanged = 'notifications/tools/list_changed';
  static const ping = 'ping';
}

// ─── helpers ───────────────────────────────────────────────────────────────

Map<String, dynamic>? _mapOrNull(Object? v) {
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}
