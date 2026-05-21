/// JSON-RPC 2.0 message types, shared between the ACP and MCP servers.
///
/// Pure data — no I/O, no transport. See `codec.dart` for serialization
/// and `transport/stdio.dart` for line-delimited framing.
library;

/// Sealed type for all JSON-RPC messages flowing in either direction.
sealed class JsonRpcMessage {
  const JsonRpcMessage();
}

/// A JSON-RPC request — has an [id] and expects a [JsonRpcResponse].
class JsonRpcRequest extends JsonRpcMessage {
  const JsonRpcRequest({required this.id, required this.method, this.params});

  /// Either an int or a String per JSON-RPC 2.0 §3.
  final Object id;
  final String method;
  final Map<String, Object?>? params;
}

/// A JSON-RPC notification — no [id], no response expected.
class JsonRpcNotification extends JsonRpcMessage {
  const JsonRpcNotification({required this.method, this.params});

  final String method;
  final Map<String, Object?>? params;
}

/// A successful response.
class JsonRpcResponse extends JsonRpcMessage {
  const JsonRpcResponse({required this.id, required this.result});

  final Object id;
  final Object? result;
}

/// An error response.
class JsonRpcError extends JsonRpcMessage {
  const JsonRpcError({
    required this.id,
    required this.code,
    required this.message,
    this.data,
  });

  /// Null only for parse errors that arrive before we can read the id.
  final Object? id;
  final int code;
  final String message;
  final Object? data;
}

/// Standard JSON-RPC 2.0 error codes (§5.1) plus a Glue-reserved range.
abstract final class JsonRpcErrorCode {
  /// Invalid JSON received by the server.
  static const int parseError = -32700;

  /// The JSON sent is not a valid Request object.
  static const int invalidRequest = -32600;

  /// The method does not exist or is not available.
  static const int methodNotFound = -32601;

  /// Invalid method parameter(s).
  static const int invalidParams = -32602;

  /// Internal JSON-RPC error.
  static const int internalError = -32603;

  // -32000 to -32099 are reserved for implementation-defined server errors.

  /// Glue-reserved: the user denied a permission request that gated this
  /// method. ACP/MCP both surface permission denial through this code.
  static const int permissionDenied = -32000;

  /// Glue-reserved: the requested session ID is unknown or has been
  /// closed.
  static const int sessionNotFound = -32001;

  /// Glue-reserved: the agent's prompt loop was cancelled (matching
  /// `session/cancel`).
  static const int cancelled = -32002;
}
