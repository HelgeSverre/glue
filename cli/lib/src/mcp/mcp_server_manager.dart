/// MCP server manager: lifecycle management for all configured MCP servers.
library;

import 'dart:async';

import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/mcp/mcp_client.dart';
import 'package:glue/src/mcp/mcp_config.dart';
import 'package:glue/src/mcp/mcp_tool_proxy.dart';
import 'package:glue/src/mcp/mcp_transport.dart';

// ---------------------------------------------------------------------------
// Server state
// ---------------------------------------------------------------------------

/// Lifecycle status of a single MCP server connection.
enum McpServerStatus {
  disconnected,
  connecting,
  initializing,
  ready,
  error,
  shuttingDown,
}

/// Runtime state for a single MCP server connection.
class McpServerState {
  final McpServerConfig config;
  McpClient? client;
  McpServerStatus status;
  String? errorMessage;
  List<McpToolDef> tools;
  DateTime? connectedAt;
  int reconnectAttempts;

  McpServerState({required this.config})
      : status = McpServerStatus.disconnected,
        tools = const [],
        reconnectAttempts = 0;
}

// ---------------------------------------------------------------------------
// Manager
// ---------------------------------------------------------------------------

/// Manages the lifecycle of all configured MCP server connections.
///
/// On startup, connects to all servers with [McpServerConfig.autoConnect]
/// and registers their tools into the shared [agentTools] map.
///
/// Tools are keyed as `mcp:<serverId>:<toolName>` in the agent tools map.
class McpServerManager {
  final Map<String, McpServerState> _servers = {};
  final Map<String, StreamSubscription<McpNotification>> _notifSubs = {};

  /// Reference to the agent's mutable tools map.
  final Map<String, Tool> agentTools;

  McpServerManager({required this.agentTools});

  /// All known server states, keyed by server id.
  Map<String, McpServerState> get servers => Map.unmodifiable(_servers);

  /// Load configuration and register server entries.
  ///
  /// Does not connect — call [connectAll] afterwards.
  void loadConfig(McpConfig config) {
    for (final entry in config.servers.entries) {
      if (entry.value.enabled) {
        _servers[entry.key] = McpServerState(config: entry.value);
      }
    }
  }

  /// Connect all servers with [McpServerConfig.autoConnect].
  ///
  /// Connection errors are silently swallowed so startup is never blocked.
  Future<void> connectAll() async {
    for (final id in _servers.keys.toList()) {
      final state = _servers[id]!;
      if (state.config.autoConnect) {
        try {
          await connect(id);
        } catch (_) {
          // Connection failure is non-fatal at startup.
        }
      }
    }
  }

  /// Connect to a specific MCP server by id.
  ///
  /// Throws if the server id is unknown or the connection fails.
  Future<void> connect(String serverId) async {
    final state = _servers[serverId];
    if (state == null) throw ArgumentError('Unknown MCP server: $serverId');
    if (state.status == McpServerStatus.ready) return; // already connected

    state.status = McpServerStatus.connecting;
    state.errorMessage = null;

    try {
      final transport = _createTransport(state.config);

      // Start the transport (spawns process or opens HTTP connection).
      if (transport is McpStdioTransport) {
        await transport.start();
      } else if (transport is McpSseTransport) {
        await transport.start();
      }

      state.client = McpClient(transport);
      state.status = McpServerStatus.initializing;

      await state.client!.initialize();

      state.status = McpServerStatus.ready;
      state.connectedAt = DateTime.now();
      state.reconnectAttempts = 0;

      // Discover tools and register them in the agent.
      state.tools = await state.client!.listTools();
      _registerTools(serverId, state);

      // Listen for tool list changes.
      _notifSubs[serverId] =
          state.client!.notifications.listen((notification) async {
        if (notification.method == 'notifications/tools/list_changed') {
          await _refreshTools(serverId);
        }
      });
    } catch (e) {
      state.status = McpServerStatus.error;
      state.errorMessage = e.toString();
      state.client = null;
      rethrow;
    }
  }

  /// Disconnect from a specific MCP server.
  Future<void> disconnect(String serverId) async {
    final state = _servers[serverId];
    if (state == null) return;
    if (state.status == McpServerStatus.disconnected) return;

    state.status = McpServerStatus.shuttingDown;
    await _notifSubs.remove(serverId)?.cancel();

    _unregisterTools(serverId);

    try {
      await state.client?.shutdown();
    } catch (_) {
      // Best-effort shutdown.
    }
    state.client = null;
    state.tools = const [];
    state.status = McpServerStatus.disconnected;
  }

  /// Gracefully disconnect from all servers.
  Future<void> disposeAll() async {
    for (final id in _servers.keys.toList()) {
      await disconnect(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Tool registration
  // ---------------------------------------------------------------------------

  void _registerTools(String serverId, McpServerState state) {
    for (final toolDef in state.tools) {
      final key = 'mcp:$serverId:${toolDef.name}';
      agentTools[key] = McpToolProxy(
        serverId: serverId,
        def: toolDef,
        client: state.client!,
      );
    }
  }

  void _unregisterTools(String serverId) {
    agentTools.removeWhere((key, _) => key.startsWith('mcp:$serverId:'));
  }

  Future<void> _refreshTools(String serverId) async {
    final state = _servers[serverId];
    if (state?.client == null) return;
    try {
      state!.tools = await state.client!.listTools();
      _unregisterTools(serverId);
      _registerTools(serverId, state);
    } catch (_) {
      // Refresh failures are non-fatal.
    }
  }

  // ---------------------------------------------------------------------------
  // Transport factory
  // ---------------------------------------------------------------------------

  McpTransport _createTransport(McpServerConfig config) {
    return switch (config.transport) {
      McpStdioConfig(:final command, :final args, :final env) =>
        McpStdioTransport(
          command: command,
          args: args,
          env: env.isEmpty ? null : env,
        ),
      McpSseConfig(:final url, :final headers) => McpSseTransport(
          endpoint: url,
          headers: _buildHeaders(config, headers),
        ),
      McpStreamableHttpConfig(:final url, :final headers) =>
        McpStreamableHttpTransport(
          endpoint: url,
          headers: _buildHeaders(config, headers),
        ),
    };
  }

  Map<String, String> _buildHeaders(
      McpServerConfig config, Map<String, String> base) {
    final headers = Map<String, String>.from(base);
    final auth = config.auth;
    if (auth is McpTokenAuth) {
      String? token;
      if (auth.envVar != null) {
        token = const String.fromEnvironment('') != ''
            ? null
            : null; // resolved later
      }
      if (token == null && auth.storedKey != null) {
        token = auth.storedKey;
      }
      if (token != null && token.isNotEmpty) {
        headers[auth.headerName] = '${auth.headerPrefix} $token';
      }
    }
    return headers;
  }
}
