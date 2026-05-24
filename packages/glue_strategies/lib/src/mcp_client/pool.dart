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
import 'package:glue_strategies/src/mcp_client/oauth.dart';
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
    this.resourceMetadataUrl,
    this.wwwAuthenticate,
  });
  final String reauthCommand;

  /// `resource_metadata` URL from the server's `WWW-Authenticate` header,
  /// if any. Surfaces this back into [McpAuthFlowRunner.cachedResourceMetadataUrl]
  /// so the panel doesn't re-probe.
  final Uri? resourceMetadataUrl;

  /// Raw `WWW-Authenticate` header. Used by the auth flow to feed
  /// `discoverMcpAuth` directly.
  final String? wwwAuthenticate;
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
typedef McpClientFactory =
    Future<McpClient> Function(McpServerSpec spec, CredentialStore credentials);

/// Pluggable refresh-grant call. Default is `null` — the pool only
/// attempts silent refresh when a runner is configured. Production
/// wires a closure that resolves the auth-server endpoints from the
/// cached `authorizationServer` field on the spec.
typedef McpRefreshGrant =
    Future<OAuthTokens> Function(String serverId, String refreshToken);

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
    McpUrlServerSpec(:final url, :final auth, :final isWebSocket) =>
      isWebSocket
          ? () async {
              final transport = await connectMcpWebSocket(
                url: url,
                bearerToken: resolveMcpBearerToken(auth, credentials, spec.id),
              );
              return McpClient(transport: transport);
            }()
          : () async {
              final transport = McpHttpTransport(
                endpoint: url,
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
    McpRefreshGrant? refreshGrant,
  }) : _reservedToolNames = reservedToolNames ?? const {},
       _clientFactory = clientFactory ?? defaultMcpClientFactory,
       // ignore: prefer_initializing_formals
       _refreshGrant = refreshGrant {
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
  final McpRefreshGrant? _refreshGrant;

  final Map<String, McpServerSnapshot> _servers = {};
  final Map<String, McpClient> _clients = {};

  /// In-flight reconnect timers, keyed by server id. Cancelled on manual
  /// `reconnect`/`toggle`/`close` and on every successful connect.
  final Map<String, Timer> _retryTimers = {};

  /// Per-server attempt counter. Bumped before each `_connect` call;
  /// reset to 0 on successful connect or manual user action.
  final Map<String, int> _attempts = {};

  final _events = StreamController<McpPoolEvent>.broadcast();

  Stream<McpPoolEvent> get events => _events.stream;

  /// All server snapshots, in YAML order.
  Iterable<McpServerSnapshot> get servers => _servers.values;

  /// Look up a server by id (the YAML key).
  McpServerSnapshot? server(String id) => _servers[id];

  /// All tools advertised by all currently-connected servers.
  /// Namespaced names; safe to add directly to an agent's tool registry.
  Iterable<McpTool> get allTools => _servers.values.expand((s) => s.tools);

  /// Count of servers in `reconnecting`, `dead`, or `awaiting auth`
  /// state. Drives the status-bar "MCP: N unhealthy" badge.
  int get unhealthyCount {
    return _servers.values.where((s) {
      final state = s.state;
      return state is McpReconnecting ||
          state is McpDead ||
          state is McpAwaitingAuth;
    }).length;
  }

  /// Number of servers in [McpAwaitingAuth] specifically — drives the
  /// `MCP: 1 needs auth` status-bar label when the unhealthy set is
  /// auth-only.
  int get awaitingAuthCount {
    return _servers.values.where((s) => s.state is McpAwaitingAuth).length;
  }

  /// Fire `connect()` for every enabled server in parallel; don't await.
  /// Each server's tools become available as its handshake completes.
  /// Servers that fail are surfaced via [events] and left in a state
  /// the user can inspect via `glue mcp list` / `/mcp list`.
  void connectAll() {
    for (final s in _servers.values) {
      if (!s.enabled) continue;
      _connect(s);
    }
  }

  /// Reconnect a specific server. Clears `dead` state if applicable and
  /// cancels any pending automatic-retry timer so the manual action takes
  /// precedence.
  Future<void> reconnect(String serverId) async {
    final s = _servers[serverId];
    if (s == null) return;
    _cancelRetry(serverId);
    _attempts[serverId] = 0;
    await _disconnect(s);
    s.state = const McpDisconnected();
    await _connect(s);
  }

  /// Session-scoped enable/disable. Doesn't write back to config.
  Future<void> toggle(String serverId) async {
    final s = _servers[serverId];
    if (s == null) return;
    _cancelRetry(serverId);
    _attempts[serverId] = 0;
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
    for (final id in _retryTimers.keys.toList()) {
      _cancelRetry(id);
    }
    for (final s in _servers.values.toList()) {
      await _disconnect(s);
    }
    await _events.close();
  }

  // ─── private ─────────────────────────────────────────────────────────────

  Future<void> _connect(McpServerSnapshot s) async {
    final attempt = (_attempts[s.id] ?? 0) + 1;
    _attempts[s.id] = attempt;
    try {
      s.state = McpConnecting(attempt: attempt);
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
      _attempts[s.id] = 0;

      _events.add(
        McpPoolServerConnectedEvent(
          serverId: s.id,
          serverName: init.serverInfo.name,
          serverVersion: init.serverInfo.version,
          toolNames: tools.map((t) => t.name).toList(),
        ),
      );

      // Subscribe to server-side notifications.
      client.notifications.forEach((n) {
        if (n.method == McpMethod.toolsListChanged) {
          _refreshTools(s);
        }
      });
    } on McpCallFailure catch (e) {
      s.lastError = e.message ?? e.reason;
      // Clean up the half-started client if any.
      final client = _clients.remove(s.id);
      await client?.close();

      if (e.reason == 'auth_expired') {
        await _handleAuthChallenge(s, e);
        return;
      }

      _events.add(
        McpPoolServerErrorEvent(
          serverId: s.id,
          kind: _failureKind(e),
          message: s.lastError!,
        ),
      );
      _handleFailure(s, reason: e.reason, attempt: attempt);
    } catch (e) {
      s.lastError = e.toString();
      _events.add(
        McpPoolServerErrorEvent(
          serverId: s.id,
          kind: McpServerErrorKind.spawnFailed,
          message: s.lastError!,
        ),
      );
      _handleFailure(s, reason: 'spawn_failed', attempt: attempt);
    }
  }

  /// Decide whether to schedule another reconnect attempt or mark dead.
  ///
  /// When the reconnect policy is disabled or the attempt cap has been
  /// reached, the server transitions to [McpDead] (legacy behaviour).
  /// Otherwise we compute a backoff delay, transition to
  /// [McpReconnecting], emit a disconnect event carrying the attempt
  /// number + `nextAttemptIn`, and arm a timer.
  void _handleFailure(
    McpServerSnapshot s, {
    required String reason,
    required int attempt,
  }) {
    final policy = config.reconnect;
    if (!policy.enabled || attempt >= policy.maxAttempts) {
      s.state = McpDead(reason: reason);
      return;
    }
    final delay = mcpBackoff(
      attempt: attempt,
      initial: Duration(milliseconds: policy.initialDelayMs),
      max: Duration(milliseconds: policy.maxDelayMs),
    );
    s.state = McpReconnecting(
      attempt: attempt,
      nextAttemptIn: delay,
      lastError: s.lastError,
    );
    _events.add(
      McpPoolServerDisconnectedEvent(
        serverId: s.id,
        reason: McpDisconnectReason.dropped,
        reconnectAttempt: attempt,
        nextAttemptIn: delay,
      ),
    );
    _retryTimers[s.id]?.cancel();
    _retryTimers[s.id] = Timer(delay, () {
      _retryTimers.remove(s.id);
      // The server may have been toggled off (or removed) while waiting.
      final current = _servers[s.id];
      if (current == null || !current.enabled) return;
      // Guard against races with manual reconnect: if the user kicked off
      // a fresh connect attempt, the state will no longer be
      // McpReconnecting, and we should leave it alone.
      if (current.state is! McpReconnecting) return;
      _connect(current);
    });
  }

  /// Handles an `auth_expired` failure: try silent refresh once, and on
  /// failure park the server in [McpAwaitingAuth] without arming a retry
  /// timer.
  Future<void> _handleAuthChallenge(
    McpServerSnapshot s,
    McpCallFailure failure,
  ) async {
    final spec = s.spec;

    // Step A — silent refresh, if we have a refresh token + grant.
    final refresh = credentials.getField(
      'mcp:${s.id}',
      McpOAuthFields.refreshToken,
    );
    if (refresh != null && _refreshGrant != null) {
      try {
        final tokens = await _refreshGrant.call(s.id, refresh);
        final clientId = credentials.getField(
          'mcp:${s.id}',
          McpOAuthFields.clientId,
        );
        if (clientId != null) {
          storeMcpOAuthTokens(
            serverId: s.id,
            client: OAuthClient(
              clientId: clientId,
              clientSecret: credentials.getField(
                'mcp:${s.id}',
                McpOAuthFields.clientSecret,
              ),
            ),
            tokens: tokens,
            credentials: credentials,
          );
          // Single retry with fresh tokens. NOT counted against attempts.
          _attempts[s.id] = 0;
          s.state = const McpDisconnected();
          await _connect(s);
          return;
        }
      } catch (_) {
        invalidateMcpAuth(
          serverId: s.id,
          scope: McpAuthInvalidation.tokens,
          credentials: credentials,
        );
        // Fall through to AwaitingAuth.
      }
    }

    // Step B — park as awaiting-auth. No retry timer.
    s.state = McpAwaitingAuth(lastError: s.lastError);
    _events.add(
      McpPoolServerAuthRequiredEvent(
        serverId: s.id,
        reauthCommand: '/mcp auth login ${s.id}',
        resourceMetadataUrl: switch (spec) {
          McpUrlServerSpec(:final resourceMetadataUrl) => resourceMetadataUrl,
          _ => null,
        },
        wwwAuthenticate: failure.wwwAuthenticate,
      ),
    );
  }

  void _cancelRetry(String serverId) {
    _retryTimers.remove(serverId)?.cancel();
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
        _events.add(
          McpPoolToolListChangedEvent(
            serverId: s.id,
            added: added,
            removed: removed,
          ),
        );
      }
    } on McpCallFailure {
      // tools/list during a degraded connection — the next reconnect
      // will refresh again. Ignore.
    }
  }

  Future<void> _disconnect(McpServerSnapshot s) async {
    _cancelRetry(s.id);
    final client = _clients.remove(s.id);
    if (client != null) {
      await client.close();
      _events.add(
        McpPoolServerDisconnectedEvent(
          serverId: s.id,
          reason: McpDisconnectReason.shutdown,
        ),
      );
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
    McpUrlServerSpec(
      :final id,
      :final url,
      :final auth,
      :final isWebSocket,
      :final resourceMetadataUrl,
      :final authorizationServer,
      :final callTimeoutSeconds,
    ) =>
      McpUrlServerSpec(
        id: id,
        url: url,
        auth: auth,
        isWebSocket: isWebSocket,
        resourceMetadataUrl: resourceMetadataUrl,
        authorizationServer: authorizationServer,
        enabled: false,
        callTimeoutSeconds: callTimeoutSeconds,
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
    McpUrlServerSpec(
      :final id,
      :final url,
      :final auth,
      :final isWebSocket,
      :final resourceMetadataUrl,
      :final authorizationServer,
      :final callTimeoutSeconds,
    ) =>
      McpUrlServerSpec(
        id: id,
        url: url,
        auth: auth,
        isWebSocket: isWebSocket,
        resourceMetadataUrl: resourceMetadataUrl,
        authorizationServer: authorizationServer,
        enabled: true,
        callTimeoutSeconds: callTimeoutSeconds,
      ),
  };
}
