/// [McpClientPool] — one [McpClient] per configured MCP server.
///
/// The pool owns the lifecycle (connect / reconnect / disconnect /
/// shutdown), exposes the union of advertised tools to the agent, and
/// emits an [McpPoolEvent] stream that App consumes for status messages
/// and the status bar.
///
/// Why [McpPoolEvent] and not [McpServerConnectedEvent] etc. directly:
/// `SessionEvent` requires a `turnId` + monotonic `sequence`, which is
/// the session bus's job. The pool is below the session bus. When the
/// bus is wired (per `docs/plans/2026-04-29-harness-layers.md`), a thin
/// adapter will translate pool events into the typed SessionEvent
/// variants. Until then, App reads pool events directly.
library;

import 'dart:async';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/config.dart';
import 'package:glue_strategies/src/mcp_client/connection_state.dart';
import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:glue_strategies/src/mcp_client/tool_factory.dart';
import 'package:glue_strategies/src/mcp_client/transport/http_sse.dart';
import 'package:glue_strategies/src/mcp_client/transport/stdio.dart';
import 'package:glue_strategies/src/mcp_client/transport/websocket.dart';

// ─── Pool events (App-consumable shape) ────────────────────────────────────

sealed class McpPoolEvent {
  const McpPoolEvent({required this.serverId});
  final String serverId;
}

class McpPoolServerConnectedEvent extends McpPoolEvent {
  const McpPoolServerConnectedEvent({
    required super.serverId,
    required this.serverName,
    required this.serverVersion,
    required this.toolNames,
  });
  final String serverName;
  final String serverVersion;

  /// Namespaced (`<serverId>.<tool>`).
  final List<String> toolNames;
}

class McpPoolServerDisconnectedEvent extends McpPoolEvent {
  const McpPoolServerDisconnectedEvent({
    required super.serverId,
    required this.reason,
    this.reconnectAttempt = 0,
    this.nextAttemptIn = Duration.zero,
  });
  final McpDisconnectReason reason;
  final int reconnectAttempt;
  final Duration nextAttemptIn;
}

class McpPoolServerErrorEvent extends McpPoolEvent {
  const McpPoolServerErrorEvent({
    required super.serverId,
    required this.kind,
    required this.message,
  });
  final McpServerErrorKind kind;
  final String message;
}

class McpPoolServerAuthRequiredEvent extends McpPoolEvent {
  const McpPoolServerAuthRequiredEvent({
    required super.serverId,
    required this.reauthCommand,
  });
  final String reauthCommand;
}

class McpPoolToolListChangedEvent extends McpPoolEvent {
  const McpPoolToolListChangedEvent({
    required super.serverId,
    required this.added,
    required this.removed,
  });
  final List<String> added;
  final List<String> removed;
}

// ─── Transport factory (test seam) ─────────────────────────────────────────

/// Builds an [McpClient] for a given spec. Injectable so tests can use
/// in-memory transports without spawning real subprocesses or hitting
/// the network.
typedef McpClientFactory = Future<McpClient> Function(
    McpServerSpec spec, CredentialStore credentials);

/// Default factory — spawns real transports for each spec type.
Future<McpClient> defaultMcpClientFactory(
  McpServerSpec spec,
  CredentialStore credentials,
) async {
  return switch (spec) {
    McpStdioServerSpec() => () async {
        final transport = await McpStdioTransport.spawn(
          command: spec.command,
          args: spec.args,
          extraEnv: spec.env,
          workingDirectory: spec.workingDirectory,
        );
        return McpClient(transport: transport);
      }(),
    McpHttpServerSpec(:final url, :final auth) => () async {
        final transport = McpHttpTransport(
          endpoint: url,
          bearerToken: resolveMcpBearerToken(auth, credentials, spec.id),
        );
        return McpClient(transport: transport);
      }(),
    McpWebSocketServerSpec(:final url, :final auth) => () async {
        final transport = await connectMcpWebSocket(
          url: url,
          bearerToken: resolveMcpBearerToken(auth, credentials, spec.id),
        );
        return McpClient(transport: transport);
      }(),
  };
}

// ─── Server state ──────────────────────────────────────────────────────────

class McpServerSnapshot {
  McpServerSnapshot({
    required this.spec,
    required this.state,
    this.tools = const [],
    this.lastError,
  });

  final McpServerSpec spec;
  McpConnectionState state;
  List<McpTool> tools;
  String? lastError;

  String get id => spec.id;
  bool get enabled => spec.enabled;
  int get toolCount => tools.length;
}

// ─── Pool ──────────────────────────────────────────────────────────────────

class McpClientPool {
  McpClientPool({
    required this.config,
    required this.credentials,
    Set<String>? reservedToolNames,
    McpClientFactory? clientFactory,
  })  : _reservedToolNames = reservedToolNames ?? const {},
        _clientFactory = clientFactory ?? defaultMcpClientFactory {
    for (final spec in config.servers) {
      _servers[spec.id] = McpServerSnapshot(
        spec: spec,
        state: const McpDisconnected(),
      );
    }
  }

  final McpConfig config;
  final CredentialStore credentials;
  final Set<String> _reservedToolNames;
  final McpClientFactory _clientFactory;

  final Map<String, McpServerSnapshot> _servers = {};
  final Map<String, McpClient> _clients = {};
  final _events = StreamController<McpPoolEvent>.broadcast();

  Stream<McpPoolEvent> get events => _events.stream;

  /// All server snapshots, in YAML order.
  Iterable<McpServerSnapshot> get servers => _servers.values;

  /// Look up a server by id (the YAML key).
  McpServerSnapshot? server(String id) => _servers[id];

  /// All tools advertised by all currently-connected servers.
  /// Namespaced names; safe to add directly to an agent's tool registry.
  Iterable<McpTool> get allTools =>
      _servers.values.expand((s) => s.tools);

  /// Count of servers in `reconnecting` or `dead` state. Drives the
  /// status-bar "MCP: 2 dead, 1 reconnecting" badge.
  int get unhealthyCount {
    return _servers.values.where((s) {
      final state = s.state;
      return state is McpReconnecting || state is McpDead;
    }).length;
  }

  /// Fire `connect()` for every enabled server in parallel; don't await.
  /// Each server's tools become available as its handshake completes.
  /// Servers that fail are surfaced via [events] and left in a state
  /// the user can inspect via `glue mcp list` / `/mcp list`.
  void connectAll() {
    for (final s in _servers.values) {
      if (!s.enabled) continue;
      unawaited(_connect(s));
    }
  }

  /// Reconnect a specific server. Clears `dead` state if applicable.
  Future<void> reconnect(String serverId) async {
    final s = _servers[serverId];
    if (s == null) return;
    await _disconnect(s);
    s.state = const McpDisconnected();
    await _connect(s);
  }

  /// Session-scoped enable/disable. Doesn't write back to config.
  Future<void> toggle(String serverId) async {
    final s = _servers[serverId];
    if (s == null) return;
    if (_clients.containsKey(serverId)) {
      await _disconnect(s);
      _servers[serverId] = McpServerSnapshot(
        spec: _disable(s.spec),
        state: const McpDisconnected(),
      );
    } else {
      _servers[serverId] = McpServerSnapshot(
        spec: _enable(s.spec),
        state: const McpDisconnected(),
      );
      await _connect(_servers[serverId]!);
    }
  }

  Future<void> close() async {
    for (final s in _servers.values.toList()) {
      await _disconnect(s);
    }
    await _events.close();
  }

  // ─── private ─────────────────────────────────────────────────────────────

  Future<void> _connect(McpServerSnapshot s) async {
    try {
      s.state = const McpConnecting();
      final client = await _clientFactory(s.spec, credentials);
      _clients[s.id] = client;

      final init = await client.initialize();
      final descriptors = await client.listTools();
      final tools = buildMcpTools(
        client: client,
        serverId: s.id,
        descriptors: descriptors,
        reservedNames: _reservedToolNames,
      );
      s.tools = tools;
      s.state = McpConnected(
        connectedAt: DateTime.now(),
        serverName: init.serverInfo.name,
        serverVersion: init.serverInfo.version,
        protocolVersion: init.protocolVersion,
      );

      _events.add(McpPoolServerConnectedEvent(
        serverId: s.id,
        serverName: init.serverInfo.name,
        serverVersion: init.serverInfo.version,
        toolNames: tools.map((t) => t.name).toList(),
      ));

      // Subscribe to server-side notifications.
      unawaited(client.notifications.forEach((n) {
        if (n.method == McpMethod.toolsListChanged) {
          unawaited(_refreshTools(s));
        }
      }));
    } on McpCallFailure catch (e) {
      s.state = McpDead(reason: e.reason);
      s.lastError = e.message ?? e.reason;
      _events.add(McpPoolServerErrorEvent(
        serverId: s.id,
        kind: _failureKind(e),
        message: s.lastError!,
      ));
      // Clean up the half-started client if any.
      final client = _clients.remove(s.id);
      await client?.close();
    } catch (e) {
      s.state = const McpDead(reason: 'spawn_failed');
      s.lastError = e.toString();
      _events.add(McpPoolServerErrorEvent(
        serverId: s.id,
        kind: McpServerErrorKind.spawnFailed,
        message: s.lastError!,
      ));
    }
  }

  Future<void> _refreshTools(McpServerSnapshot s) async {
    final client = _clients[s.id];
    if (client == null) return;
    try {
      final descriptors = await client.listTools();
      final newTools = buildMcpTools(
        client: client,
        serverId: s.id,
        descriptors: descriptors,
        reservedNames: _reservedToolNames,
      );
      final oldNames = s.tools.map((t) => t.name).toSet();
      final newNames = newTools.map((t) => t.name).toSet();
      final added = newNames.difference(oldNames).toList();
      final removed = oldNames.difference(newNames).toList();
      s.tools = newTools;
      if (added.isNotEmpty || removed.isNotEmpty) {
        _events.add(McpPoolToolListChangedEvent(
          serverId: s.id,
          added: added,
          removed: removed,
        ));
      }
    } on McpCallFailure {
      // tools/list during a degraded connection — the next reconnect
      // will refresh again. Ignore.
    }
  }

  Future<void> _disconnect(McpServerSnapshot s) async {
    final client = _clients.remove(s.id);
    if (client != null) {
      await client.close();
      _events.add(McpPoolServerDisconnectedEvent(
        serverId: s.id,
        reason: McpDisconnectReason.shutdown,
      ));
    }
    s.tools = const [];
  }

  McpServerErrorKind _failureKind(McpCallFailure e) {
    return switch (e.reason) {
      'protocol_too_old' => McpServerErrorKind.protocolTooOld,
      'server_error' => McpServerErrorKind.transportError,
      'transport_error' => McpServerErrorKind.transportError,
      'disconnected' => McpServerErrorKind.transportError,
      'timeout' => McpServerErrorKind.transportError,
      _ => McpServerErrorKind.transportError,
    };
  }

  /// Builds a copy of [spec] with `enabled = false`. Cheap dispatch on
  /// the sealed type so we don't need a generic copyWith.
  McpServerSpec _disable(McpServerSpec spec) => switch (spec) {
        McpStdioServerSpec() => McpStdioServerSpec(
            id: spec.id,
            command: spec.command,
            args: spec.args,
            env: spec.env,
            workingDirectory: spec.workingDirectory,
            enabled: false,
            callTimeoutSeconds: spec.callTimeoutSeconds,
          ),
        McpHttpServerSpec() => McpHttpServerSpec(
            id: spec.id,
            url: spec.url,
            auth: spec.auth,
            enabled: false,
            callTimeoutSeconds: spec.callTimeoutSeconds,
          ),
        McpWebSocketServerSpec() => McpWebSocketServerSpec(
            id: spec.id,
            url: spec.url,
            auth: spec.auth,
            enabled: false,
            callTimeoutSeconds: spec.callTimeoutSeconds,
          ),
      };

  McpServerSpec _enable(McpServerSpec spec) => switch (spec) {
        McpStdioServerSpec() => McpStdioServerSpec(
            id: spec.id,
            command: spec.command,
            args: spec.args,
            env: spec.env,
            workingDirectory: spec.workingDirectory,
            enabled: true,
            callTimeoutSeconds: spec.callTimeoutSeconds,
          ),
        McpHttpServerSpec() => McpHttpServerSpec(
            id: spec.id,
            url: spec.url,
            auth: spec.auth,
            enabled: true,
            callTimeoutSeconds: spec.callTimeoutSeconds,
          ),
        McpWebSocketServerSpec() => McpWebSocketServerSpec(
            id: spec.id,
            url: spec.url,
            auth: spec.auth,
            enabled: true,
            callTimeoutSeconds: spec.callTimeoutSeconds,
          ),
      };
}
