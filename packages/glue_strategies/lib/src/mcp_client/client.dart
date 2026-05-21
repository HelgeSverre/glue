/// MCP JSON-RPC client.
///
/// Speaks MCP over an injectable [JsonRpcTransport] from glue_server so
/// the same client works against stdio, HTTP+SSE, WebSocket, or an
/// in-memory transport in tests.
///
/// Responsibilities:
///   • initialize handshake + protocol version negotiation
///   • tools/list, tools/call with a concurrent-id pending map
///   • rate-limit retry-once
///   • notifications fan-out (`tools/list_changed`, future server events)
///   • drop detection → pending calls fail with retryable metadata
library;

import 'dart:async';

import 'package:glue_server/glue_server.dart';

import 'package:glue_strategies/src/mcp_client/protocol.dart';
import 'package:glue_strategies/src/mcp_client/transport/http_sse.dart'
    show McpHttpTransportError;

/// A peer-side notification flowing from the server. `tools/list_changed`
/// is the only one we currently care about, but we surface everything so
/// callers can route as they like.
class McpNotification {
  const McpNotification({required this.method, this.params});
  final String method;
  final Map<String, dynamic>? params;
}

/// Failure shape thrown by [McpClient.callTool] / [listTools] / [initialize]
/// when the call cannot complete. The agent loop maps this onto
/// `ToolResult(success: false, ...)`.
class McpCallFailure implements Exception {
  const McpCallFailure({
    required this.reason,
    this.code,
    this.message,
    this.retryable = false,
    this.wwwAuthenticate,
  });

  /// Short machine reason. Stable. Drives metadata.
  final String reason;

  /// JSON-RPC error code if this came from the server.
  final int? code;

  /// Human-readable message.
  final String? message;

  /// Whether the agent loop may retry the same call.
  final bool retryable;

  /// Raw `WWW-Authenticate` header, when this failure originated from
  /// a 401 transport error. Consumed by the pool to drive RFC 9728
  /// discovery and refresh-token grant.
  final String? wwwAuthenticate;

  @override
  String toString() =>
      'McpCallFailure($reason${code != null ? ' code=$code' : ''}'
      '${message != null ? ' "$message"' : ''})';
}

class McpClient {
  McpClient({
    required this.transport,
    this.clientInfo = const McpClientInfo(name: 'glue', version: '0.0.0'),
    this.clientCapabilities = const McpClientCapabilities(
      roots: McpRootsCapability(listChanged: true),
    ),
    this.callTimeout = const Duration(seconds: 30),
  }) {
    _incomingSub = transport.incoming.listen(
      _handleIncoming,
      onError: _handleTransportError,
      onDone: _handleTransportDone,
    );
  }

  final JsonRpcTransport transport;
  final McpClientInfo clientInfo;
  final McpClientCapabilities clientCapabilities;
  final Duration callTimeout;

  int _nextId = 1;
  final _pending = <int, Completer<JsonRpcResponse>>{};
  final _notifications = StreamController<McpNotification>.broadcast();
  StreamSubscription<JsonRpcMessage>? _incomingSub;
  bool _closed = false;
  McpInitializeResult? _initResult;

  Stream<McpNotification> get notifications => _notifications.stream;

  /// Set after a successful [initialize]. Null otherwise.
  McpInitializeResult? get initResult => _initResult;

  /// Sends `initialize` + `notifications/initialized`. Negotiates the
  /// protocol version per the design doc: equal → continue; older within
  /// minimum-supported → continue with downgrade; newer → continue,
  /// upgrade-tolerant; older than minimum → refuse.
  Future<McpInitializeResult> initialize() async {
    final result = await _request(McpMethod.initialize, {
      'protocolVersion': mcpProtocolVersion,
      'clientInfo': clientInfo.toJson(),
      'capabilities': clientCapabilities.toJson(),
    });
    final parsed = McpInitializeResult.fromJson(
      (result as Map).cast<String, dynamic>(),
    );

    if (parsed.protocolVersion.isEmpty ||
        _compareProtocol(parsed.protocolVersion, mcpMinimumProtocolVersion) <
            0) {
      throw McpCallFailure(
        reason: 'protocol_too_old',
        message:
            'Server protocolVersion="${parsed.protocolVersion}" below minimum '
            '"$mcpMinimumProtocolVersion"',
      );
    }

    _initResult = parsed;
    _notify(McpMethod.initialized);
    return parsed;
  }

  Future<List<McpToolDescriptor>> listTools() async {
    final result = await _request(McpMethod.toolsList, const {});
    final list = (result as Map<String, dynamic>)['tools'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(McpToolDescriptor.fromJson)
        .toList();
  }

  /// Calls a tool. On JSON-RPC rate-limit (`-32011`) we honour the hint
  /// and retry once. On transport drop, all pending calls (including
  /// this one) resolve with [McpCallFailure(retryable: true)].
  Future<McpToolCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final result = await _request(McpMethod.toolsCall, {
        'name': name,
        'arguments': arguments,
      });
      return McpToolCallResult.fromJson(
        (result as Map).cast<String, dynamic>(),
      );
    } on McpCallFailure catch (e) {
      if (e.code != McpErrorCode.rateLimited) rethrow;
      // Retry once after the server-suggested delay.
      // Currently we don't have access to the structured `data` field
      // here — defer to a fixed short wait. A follow-up will plumb the
      // server's `retry_after_seconds` through.
      await Future<void>.delayed(const Duration(seconds: 1));
      final result = await _request(McpMethod.toolsCall, {
        'name': name,
        'arguments': arguments,
      });
      return McpToolCallResult.fromJson(
        (result as Map).cast<String, dynamic>(),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failAllPending(const McpCallFailure(reason: 'shutdown', retryable: false));
    await _incomingSub?.cancel();
    _incomingSub = null;
    await transport.close();
    await _notifications.close();
  }

  // ─── private ─────────────────────────────────────────────────────────────

  Future<Object?> _request(String method, Map<String, dynamic> params) async {
    if (_closed) {
      throw const McpCallFailure(
        reason: 'closed',
        message: 'client has been closed',
      );
    }
    final id = _nextId++;
    final completer = Completer<JsonRpcResponse>();
    _pending[id] = completer;
    transport.send(JsonRpcRequest(id: id, method: method, params: params));
    try {
      final response = await completer.future.timeout(callTimeout);
      return response.result;
    } on TimeoutException {
      _pending.remove(id);
      throw McpCallFailure(
        reason: 'timeout',
        message: 'request "$method" timed out after ${callTimeout.inSeconds}s',
        retryable: true,
      );
    }
  }

  void _notify(String method, [Map<String, dynamic>? params]) {
    if (_closed) return;
    transport.send(JsonRpcNotification(method: method, params: params));
  }

  void _handleIncoming(JsonRpcMessage msg) {
    switch (msg) {
      case JsonRpcResponse(:final id):
        final intId = _coerceId(id);
        final c = intId != null ? _pending.remove(intId) : null;
        c?.complete(msg);
      case JsonRpcError(:final id, :final code, :final message):
        final intId = _coerceId(id);
        final c = intId != null ? _pending.remove(intId) : null;
        c?.completeError(
          McpCallFailure(
            reason: 'server_error',
            code: code,
            message: message,
            retryable: code == McpErrorCode.rateLimited,
          ),
        );
      case JsonRpcNotification(:final method, :final params):
        _notifications.add(McpNotification(method: method, params: params));
      case JsonRpcRequest():
        // Servers may send requests (e.g. sampling). We don't support any
        // server→client requests in v1; reply with method-not-found so
        // the server gets a clean negative rather than a hang.
        transport.send(
          JsonRpcError(
            id: msg.id,
            code: -32601,
            message: 'Method not found: ${msg.method}',
          ),
        );
    }
  }

  void _handleTransportError(Object error) {
    if (error is McpHttpTransportError && error.statusCode == 401) {
      _failAllPending(
        McpCallFailure(
          reason: 'auth_expired',
          message: error.body.isEmpty ? '401 Unauthorized' : error.body,
          retryable: true,
          wwwAuthenticate: error.wwwAuthenticate,
        ),
      );
      return;
    }
    _failAllPending(
      McpCallFailure(
        reason: 'transport_error',
        message: error.toString(),
        retryable: true,
      ),
    );
  }

  void _handleTransportDone() {
    _failAllPending(
      const McpCallFailure(
        reason: 'disconnected',
        message: 'transport closed',
        retryable: true,
      ),
    );
  }

  void _failAllPending(McpCallFailure failure) {
    if (_pending.isEmpty) return;
    final pending = Map<int, Completer<JsonRpcResponse>>.from(_pending);
    _pending.clear();
    for (final c in pending.values) {
      if (!c.isCompleted) c.completeError(failure);
    }
  }

  /// JSON-RPC ids may be int or string; we always send ints.
  int? _coerceId(Object? id) {
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }
}

/// Compares two MCP version strings (`YYYY-MM-DD` lex-compare works
/// because the format is fixed-width). Returns -1/0/1.
int _compareProtocol(String a, String b) => a.compareTo(b);
