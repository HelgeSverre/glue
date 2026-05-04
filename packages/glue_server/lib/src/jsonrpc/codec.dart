/// Encodes JSON-RPC messages to/from the wire format.
///
/// Pure functions; no I/O. See `transport/stdio.dart` for the stdio
/// framing that drives this codec.
library;

import 'dart:convert';

import 'package:glue_server/src/jsonrpc/messages.dart';

/// Serializes a [JsonRpcMessage] to its on-the-wire JSON object form.
Map<String, Object?> encodeJsonRpc(JsonRpcMessage message) {
  return switch (message) {
    JsonRpcRequest(:final id, :final method, :final params) => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      },
    JsonRpcNotification(:final method, :final params) => {
        'jsonrpc': '2.0',
        'method': method,
        if (params != null) 'params': params,
      },
    JsonRpcResponse(:final id, :final result) => {
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      },
    JsonRpcError(:final id, :final code, :final message, :final data) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': code,
          'message': message,
          if (data != null) 'data': data,
        },
      },
  };
}

/// Encodes a [JsonRpcMessage] as a single JSON string.
String encodeJsonRpcString(JsonRpcMessage message) =>
    jsonEncode(encodeJsonRpc(message));

/// Decodes a parsed JSON object into the right [JsonRpcMessage] subtype.
///
/// Returns a [JsonRpcError] with [JsonRpcErrorCode.invalidRequest] if
/// the payload is structurally wrong; throws [FormatException] for
/// shapes the server should treat as parse errors.
JsonRpcMessage decodeJsonRpc(Map<String, Object?> payload) {
  final jsonrpc = payload['jsonrpc'];
  if (jsonrpc != '2.0') {
    return JsonRpcError(
      id: payload['id'],
      code: JsonRpcErrorCode.invalidRequest,
      message: 'jsonrpc field must be "2.0"',
    );
  }

  final hasError = payload.containsKey('error');
  final hasResult = payload.containsKey('result');
  final hasId = payload.containsKey('id');
  final hasMethod = payload.containsKey('method');

  if (hasError && hasId) {
    final errMap = payload['error'];
    if (errMap is! Map) {
      return JsonRpcError(
        id: payload['id'],
        code: JsonRpcErrorCode.invalidRequest,
        message: 'error field must be an object',
      );
    }
    final err = errMap.cast<String, Object?>();
    return JsonRpcError(
      id: payload['id'],
      code: (err['code'] as num?)?.toInt() ?? JsonRpcErrorCode.internalError,
      message: (err['message'] as String?) ?? '',
      data: err['data'],
    );
  }

  if (hasResult && hasId) {
    return JsonRpcResponse(id: payload['id']!, result: payload['result']);
  }

  if (hasMethod) {
    final method = payload['method'];
    if (method is! String) {
      return JsonRpcError(
        id: payload['id'],
        code: JsonRpcErrorCode.invalidRequest,
        message: 'method must be a string',
      );
    }
    final paramsRaw = payload['params'];
    final params = paramsRaw is Map ? paramsRaw.cast<String, Object?>() : null;
    if (hasId) {
      return JsonRpcRequest(
        id: payload['id']!,
        method: method,
        params: params,
      );
    }
    return JsonRpcNotification(method: method, params: params);
  }

  return JsonRpcError(
    id: payload['id'],
    code: JsonRpcErrorCode.invalidRequest,
    message: 'message must be a request, response, error, or notification',
  );
}

/// Decodes a single JSON string into a [JsonRpcMessage]. Returns a
/// `JsonRpcError(parseError)` if the line is not valid JSON.
JsonRpcMessage decodeJsonRpcString(String line) {
  final dynamic raw;
  try {
    raw = jsonDecode(line);
  } on FormatException catch (e) {
    return JsonRpcError(
      id: null,
      code: JsonRpcErrorCode.parseError,
      message: 'invalid JSON: ${e.message}',
    );
  }
  if (raw is! Map) {
    return const JsonRpcError(
      id: null,
      code: JsonRpcErrorCode.parseError,
      message: 'top-level JSON must be an object',
    );
  }
  return decodeJsonRpc(raw.cast<String, Object?>());
}
