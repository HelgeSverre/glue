/// Connection state machine for an [McpClient] against a single MCP
/// server, plus the backoff-with-jitter helper.
///
/// Pure data + a pure function. The state-transition logic itself lives
/// in `client.dart` and `pool.dart`.
///
/// [McpDisconnectReason] re-exports from `glue_core` so the wire enum
/// stays single-sourced — the same value flows through events and the
/// state machine.
library;

import 'dart:math';

export 'package:glue_core/glue_core.dart' show McpDisconnectReason;

sealed class McpConnectionState {
  const McpConnectionState();
}

class McpDisconnected extends McpConnectionState {
  const McpDisconnected();
}

class McpConnecting extends McpConnectionState {
  const McpConnecting({this.attempt = 1});
  final int attempt;
}

class McpConnected extends McpConnectionState {
  const McpConnected({
    required this.connectedAt,
    required this.serverName,
    required this.serverVersion,
    required this.protocolVersion,
  });
  final DateTime connectedAt;
  final String serverName;
  final String serverVersion;
  final String protocolVersion;
}

class McpReconnecting extends McpConnectionState {
  const McpReconnecting({
    required this.attempt,
    required this.nextAttemptIn,
    this.lastError,
  });
  final int attempt;
  final Duration nextAttemptIn;
  final String? lastError;
}

class McpDead extends McpConnectionState {
  const McpDead({required this.reason});
  final String reason;
}

/// Server is parked because OAuth is required. Distinct from [McpDead]:
/// no reconnect timer armed, no budget consumed. Cleared by a successful
/// auth flow (via `pool.reconnect`).
class McpAwaitingAuth extends McpConnectionState {
  const McpAwaitingAuth({this.lastError});
  final String? lastError;
}

/// Backoff delay for reconnection attempts, with jitter.
///
/// `attempt` is 1-indexed. Returns
/// `min(initial * 2^(attempt-1), max) + random(0, jitterFraction * delay)`.
///
/// Defaults match the design doc (initial 500ms, max 30s, jitter 30%).
Duration mcpBackoff({
  required int attempt,
  Duration initial = const Duration(milliseconds: 500),
  Duration max = const Duration(seconds: 30),
  double jitterFraction = 0.3,
  Random? random,
}) {
  // Clamp the shift before computing to avoid int overflow on large attempts.
  final shift = (attempt - 1).clamp(0, 30);
  final base = initial.inMilliseconds * (1 << shift);
  final clamped = base.clamp(0, max.inMilliseconds).toInt();
  final r = random ?? Random();
  final jitterMs = (clamped * jitterFraction * r.nextDouble()).round();
  return Duration(milliseconds: clamped + jitterMs);
}
