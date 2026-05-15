/// WebSocket transport for MCP.
///
/// Connects to `ws://` / `wss://` URLs. Each frame is one JSON-RPC
/// message — no extra framing needed since WebSocket preserves message
/// boundaries.
///
/// The existing [WebSocketTransport] in glue_server already implements
/// the wire layer for a server-side handle. This file is the client-
/// side connection establishment (with optional bearer auth header)
/// plus a thin wrapper that just exposes the transport via the same
/// [JsonRpcTransport] interface.
library;

import 'dart:io';

import 'package:glue_server/glue_server.dart';

class McpWebSocketConnectError implements Exception {
  const McpWebSocketConnectError(this.url, this.cause);
  final Uri url;
  final Object cause;
  @override
  String toString() => 'McpWebSocketConnectError($url): $cause';
}

/// Establishes the WebSocket connection and returns a transport.
///
/// `bearerToken` is sent as `Authorization: Bearer …` during the
/// upgrade handshake. Note: browsers cannot set custom WebSocket
/// upgrade headers, but Dart's `dart:io` WebSocket client can — so
/// this works for CLI/native users. Web users would need to fall back
/// to a query-string token or HTTP+SSE.
Future<JsonRpcTransport> connectMcpWebSocket({
  required Uri url,
  String? bearerToken,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (url.scheme != 'ws' && url.scheme != 'wss') {
    throw ArgumentError.value(
      url,
      'url',
      'WebSocket URL must use ws:// or wss://',
    );
  }
  final headers = <String, Object>{
    if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
  };
  try {
    // The socket's lifetime is owned by the returned transport, which
    // closes it in `WebSocketTransport.close`. The linter can't see
    // through the wrapping ctor so we silence the false positive.
    // ignore: close_sinks
    final socket = await WebSocket.connect(
      url.toString(),
      headers: headers,
    ).timeout(timeout);
    return WebSocketTransport(socket);
  } catch (e) {
    throw McpWebSocketConnectError(url, e);
  }
}
