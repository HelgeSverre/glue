/// MCP transport layer: stdio, SSE, and streamable HTTP.
///
/// Each transport implements [McpTransport], which provides request/response
/// and notification semantics over the underlying wire.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:glue/src/llm/sse.dart';

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

/// A server-initiated notification (no response expected).
class McpNotification {
  final String method;
  final Map<String, dynamic>? params;

  const McpNotification({required this.method, this.params});
}

/// Base interface for all MCP transports.
abstract class McpTransport {
  /// Send a JSON-RPC request and wait for the response payload.
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
  );

  /// Send a JSON-RPC notification (fire-and-forget).
  Future<void> notify(String method, Map<String, dynamic>? params);

  /// Stream of server-initiated notifications.
  Stream<McpNotification> get notifications;

  /// Close the transport.
  Future<void> close();
}

// ---------------------------------------------------------------------------
// Stdio transport
// ---------------------------------------------------------------------------

/// MCP transport that communicates with a local child process over
/// stdin/stdout using newline-delimited JSON-RPC 2.0.
class McpStdioTransport implements McpTransport {
  final String command;
  final List<String> args;
  final Map<String, String>? env;

  Process? _process;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final _notificationController = StreamController<McpNotification>.broadcast();
  StreamSubscription<String>? _stdoutSub;
  bool _closed = false;

  McpStdioTransport({
    required this.command,
    this.args = const [],
    this.env,
  });

  Future<void> start() async {
    if (_process != null) return;
    _process = await Process.start(
      command,
      args,
      environment: env,
      runInShell: false,
    );

    // Read stdout line by line and dispatch JSON-RPC messages.
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _handleProcessExit);

    // Discard stderr (captured for diagnostics if needed).
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {}); // ignore stderr
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return; // Skip malformed JSON
    }

    final id = message['id'];
    if (id != null) {
      // Response to a pending request.
      final completer = _pending.remove(id is double ? id.toInt() : id as int?);
      if (completer != null && !completer.isCompleted) {
        final error = message['error'];
        if (error != null) {
          final errMap = error is Map ? Map<String, dynamic>.from(error) : {};
          completer.completeError(
            McpError(
              code: errMap['code'] as int? ?? -1,
              message: errMap['message'] as String? ?? 'Unknown error',
              data: errMap['data'],
            ),
          );
        } else {
          final result = message['result'];
          completer.complete(
            result is Map
                ? Map<String, dynamic>.from(result)
                : <String, dynamic>{},
          );
        }
      }
    } else {
      // Notification (no id).
      final method = message['method'] as String?;
      if (method != null && !_notificationController.isClosed) {
        final params = message['params'];
        _notificationController.add(McpNotification(
          method: method,
          params: params is Map ? Map<String, dynamic>.from(params) : null,
        ));
      }
    }
  }

  void _handleProcessExit() {
    // Fail all pending requests.
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const McpTransportError('Process exited'));
      }
    }
    _pending.clear();
    if (!_notificationController.isClosed) {
      _notificationController.close();
    }
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
  ) async {
    if (_closed) throw const McpTransportError('Transport is closed');
    final process = _process;
    if (process == null) throw const McpTransportError('Transport not started');

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final envelope = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    process.stdin.writeln(jsonEncode(envelope));

    return completer.future;
  }

  @override
  Future<void> notify(String method, Map<String, dynamic>? params) async {
    if (_closed) return;
    final process = _process;
    if (process == null) return;

    final envelope = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    };
    process.stdin.writeln(jsonEncode(envelope));
  }

  @override
  Stream<McpNotification> get notifications => _notificationController.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stdoutSub?.cancel();
    try {
      await _process?.stdin.flush();
      await _process?.stdin.close();
    } catch (_) {}
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    if (!_notificationController.isClosed) {
      await _notificationController.close();
    }
  }
}

// ---------------------------------------------------------------------------
// SSE transport
// ---------------------------------------------------------------------------

/// MCP transport using HTTP POST (client→server) + SSE (server→client).
///
/// This is the legacy MCP HTTP transport where:
///   - The client connects to a long-lived SSE endpoint to receive messages.
///   - The client POSTs JSON-RPC requests to the endpoint URL.
class McpSseTransport implements McpTransport {
  final Uri endpoint;
  final Map<String, String> headers;
  final http.Client _client;

  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final _notificationController = StreamController<McpNotification>.broadcast();
  StreamSubscription<SseEvent>? _sseSub;
  bool _closed = false;

  /// URL for POSTing requests (may differ from SSE endpoint).
  Uri? _postUrl;

  McpSseTransport({
    required this.endpoint,
    this.headers = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<void> start() async {
    // Open the SSE stream and wait for the endpoint event.
    final req = http.Request('GET', endpoint)
      ..headers.addAll({
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...headers,
      });
    final response = await _client.send(req);
    if (response.statusCode != 200) {
      throw McpTransportError(
          'SSE connection failed: HTTP ${response.statusCode}');
    }

    _sseSub =
        decodeSse(response.stream).listen(_handleSseEvent, onDone: _onDone);
  }

  void _handleSseEvent(SseEvent event) {
    if (event.data.isEmpty) return;

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(event.data);
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } on FormatException {
      // The `endpoint` event carries the POST URL as plain text.
      if (event.event == 'endpoint') {
        final rawUrl = event.data.trim();
        _postUrl = endpoint.resolve(rawUrl);
      }
      return;
    }

    final id = message['id'];
    if (id != null) {
      final intId = id is double ? id.toInt() : (id as int? ?? -1);
      final completer = _pending.remove(intId);
      if (completer != null && !completer.isCompleted) {
        final error = message['error'];
        if (error != null) {
          final errMap = error is Map ? Map<String, dynamic>.from(error) : {};
          completer.completeError(McpError(
            code: errMap['code'] as int? ?? -1,
            message: errMap['message'] as String? ?? 'Unknown error',
          ));
        } else {
          final result = message['result'];
          completer.complete(
            result is Map
                ? Map<String, dynamic>.from(result)
                : <String, dynamic>{},
          );
        }
      }
    } else {
      final method = message['method'] as String?;
      if (method != null && !_notificationController.isClosed) {
        final params = message['params'];
        _notificationController.add(McpNotification(
          method: method,
          params: params is Map ? Map<String, dynamic>.from(params) : null,
        ));
      }
    }
  }

  void _onDone() {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(const McpTransportError('SSE closed'));
      }
    }
    _pending.clear();
    if (!_notificationController.isClosed) _notificationController.close();
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
  ) async {
    if (_closed) throw const McpTransportError('Transport is closed');
    final postUrl = _postUrl ?? endpoint;

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });

    await _client.post(
      postUrl,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: body,
    );

    return completer.future;
  }

  @override
  Future<void> notify(String method, Map<String, dynamic>? params) async {
    if (_closed) return;
    final postUrl = _postUrl ?? endpoint;

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    });

    await _client.post(
      postUrl,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
      body: body,
    );
  }

  @override
  Stream<McpNotification> get notifications => _notificationController.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sseSub?.cancel();
    _client.close();
    if (!_notificationController.isClosed) {
      await _notificationController.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Streamable HTTP transport
// ---------------------------------------------------------------------------

/// MCP transport using streamable HTTP (the modern MCP transport).
///
/// POSTs JSON-RPC requests to the endpoint. Response may be either a plain
/// JSON object or an SSE stream (based on Content-Type).
class McpStreamableHttpTransport implements McpTransport {
  final Uri endpoint;
  final Map<String, String> headers;
  final http.Client _client;

  int _nextId = 1;
  final _notificationController = StreamController<McpNotification>.broadcast();
  String? _sessionId;
  bool _closed = false;

  McpStreamableHttpTransport({
    required this.endpoint,
    this.headers = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
  ) async {
    if (_closed) throw const McpTransportError('Transport is closed');

    final id = _nextId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });

    final req = http.Request('POST', endpoint)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        if (_sessionId != null) 'Mcp-Session-Id': _sessionId!,
        ...headers,
      })
      ..body = body;

    final response = await _client.send(req);

    // Capture session id for subsequent requests.
    final newSession = response.headers['mcp-session-id'];
    if (newSession != null && newSession.isNotEmpty) {
      _sessionId = newSession;
    }

    final contentType = response.headers['content-type'] ?? '';

    if (contentType.contains('text/event-stream')) {
      // Parse as SSE and return the first response event.
      await for (final event in decodeSse(response.stream)) {
        if (event.event == 'message' || event.event == null) {
          try {
            final decoded = jsonDecode(event.data);
            if (decoded is Map) {
              final msg = Map<String, dynamic>.from(decoded);
              // Check if it's a notification.
              if (msg['id'] == null && msg['method'] != null) {
                final method = msg['method'] as String;
                final notifParams = msg['params'];
                if (!_notificationController.isClosed) {
                  _notificationController.add(McpNotification(
                    method: method,
                    params: notifParams is Map
                        ? Map<String, dynamic>.from(notifParams)
                        : null,
                  ));
                }
                continue;
              }
              final result = msg['result'];
              return result is Map
                  ? Map<String, dynamic>.from(result)
                  : <String, dynamic>{};
            }
          } on FormatException {
            continue;
          }
        }
      }
      throw const McpTransportError('No response received in SSE stream');
    }

    // Plain JSON response.
    final bytes = await response.stream.toBytes();
    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const McpTransportError('Unexpected response format');
    }
    final msg = Map<String, dynamic>.from(decoded);
    final error = msg['error'];
    if (error != null) {
      final errMap = error is Map ? Map<String, dynamic>.from(error) : {};
      throw McpError(
        code: errMap['code'] as int? ?? -1,
        message: errMap['message'] as String? ?? 'Unknown error',
      );
    }
    final result = msg['result'];
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  @override
  Future<void> notify(String method, Map<String, dynamic>? params) async {
    if (_closed) return;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    });
    try {
      await _client.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json',
          if (_sessionId != null) 'Mcp-Session-Id': _sessionId!,
          ...headers,
        },
        body: body,
      );
    } catch (_) {
      // Notifications are fire-and-forget; ignore errors.
    }
  }

  @override
  Stream<McpNotification> get notifications => _notificationController.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
    if (!_notificationController.isClosed) {
      await _notificationController.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Error types
// ---------------------------------------------------------------------------

/// A JSON-RPC error response from an MCP server.
class McpError implements Exception {
  final int code;
  final String message;
  final dynamic data;

  const McpError({
    required this.code,
    required this.message,
    this.data,
  });

  @override
  String toString() => 'McpError($code): $message';
}

/// A transport-level error (not a JSON-RPC error).
class McpTransportError implements Exception {
  final String message;

  const McpTransportError(this.message);

  @override
  String toString() => 'McpTransportError: $message';
}
