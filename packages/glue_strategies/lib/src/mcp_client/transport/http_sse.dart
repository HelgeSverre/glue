/// Streamable HTTP transport for MCP (2025-03-26 spec).
///
/// Single endpoint. Each client→server message is one POST. The server
/// responds with either:
///   • `Content-Type: application/json` — a single JSON-RPC message
///   • `Content-Type: text/event-stream` — zero or more JSON-RPC
///     messages in SSE events (`data: {...}`)
///
/// Authentication is via `Authorization: Bearer <token>`. Session state
/// across requests uses the `Mcp-Session-Id` header (captured from the
/// initialize response, sent back on every subsequent request).
///
/// Out of scope for v1:
///   • Standalone GET-SSE channel for server-initiated notifications.
///     For HTTP-bound servers, tools/list_changed lands in B7 alongside
///     the rest of the ACP integration.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue_server/glue_server.dart';
import 'package:http/http.dart' as http;

import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/llm/sse.dart';
import 'package:glue_strategies/src/mcp_client/config.dart';

class McpHttpTransport implements JsonRpcTransport {
  McpHttpTransport({
    required this.endpoint,
    this.bearerToken,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  final Uri endpoint;

  /// Optional bearer token. When set, every request carries
  /// `Authorization: Bearer <token>`.
  final String? bearerToken;

  final http.Client _client;
  final _incoming = StreamController<JsonRpcMessage>.broadcast();
  bool _closed = false;

  /// Captured from the initialize response (if any). Forwarded on
  /// subsequent requests so the server can stitch them together.
  String? _sessionId;

  @override
  Stream<JsonRpcMessage> get incoming => _incoming.stream;

  @override
  void send(JsonRpcMessage message) {
    if (_closed) return;
    _send(message);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
    await _incoming.close();
  }

  // ─── private ─────────────────────────────────────────────────────────────

  Future<void> _send(JsonRpcMessage message) async {
    final body = encodeJsonRpcString(message);
    final req = http.Request('POST', endpoint);
    req.headers['Content-Type'] = 'application/json';
    req.headers['Accept'] = 'application/json, text/event-stream';
    if (bearerToken != null) {
      req.headers['Authorization'] = 'Bearer $bearerToken';
    }
    if (_sessionId != null) {
      req.headers['Mcp-Session-Id'] = _sessionId!;
    }
    req.body = body;

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(req);
    } catch (e) {
      if (!_closed) _incoming.addError(e);
      return;
    }

    // Capture session id from the response (canonical header is
    // `Mcp-Session-Id`; servers also commonly use lowercase).
    final sessionId =
        streamed.headers['mcp-session-id'] ??
        streamed.headers['Mcp-Session-Id'];
    if (sessionId != null && sessionId.isNotEmpty) {
      _sessionId = sessionId;
    }

    // 202 Accepted with no body is the canonical response to a
    // notification — server has nothing to say back. Drain and return.
    if (streamed.statusCode == 202) {
      await streamed.stream.drain<void>();
      return;
    }

    if (streamed.statusCode >= 400) {
      final bodyBytes = await streamed.stream.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      final text = utf8.decode(bodyBytes, allowMalformed: true);
      final wwwAuth =
          streamed.headers['www-authenticate'] ??
          streamed.headers['WWW-Authenticate'];
      if (!_closed) {
        _incoming.addError(
          McpHttpTransportError(
            statusCode: streamed.statusCode,
            body: text,
            wwwAuthenticate: wwwAuth,
          ),
        );
      }
      return;
    }

    final contentType = (streamed.headers['content-type'] ?? '').toLowerCase();

    if (contentType.contains('text/event-stream')) {
      // One or more messages over SSE.
      try {
        await for (final event in decodeSse(streamed.stream)) {
          if (_closed) return;
          _emit(event.data);
        }
      } catch (e) {
        if (!_closed) _incoming.addError(e);
      }
      return;
    }

    // Default to JSON.
    final bytes = await streamed.stream.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return; // Empty 200 (rare) — nothing to dispatch.
    _emit(text);
  }

  void _emit(String text) {
    if (text.isEmpty) return;
    try {
      _incoming.add(decodeJsonRpcString(text));
    } catch (e) {
      _incoming.addError(e);
    }
  }
}

/// Surfaced via the [JsonRpcTransport.incoming] stream's error channel
/// when the server returns a non-2xx HTTP status. The [McpClient] in
/// turn maps it to an [McpCallFailure] for the agent loop.
///
/// On 401 responses the [wwwAuthenticate] header (if any) is captured
/// — the pool consumes it to discover OAuth metadata per RFC 9728.
class McpHttpTransportError implements Exception {
  const McpHttpTransportError({
    required this.statusCode,
    required this.body,
    this.wwwAuthenticate,
  });
  final int statusCode;
  final String body;

  /// Raw `WWW-Authenticate` header from the response. Populated when
  /// the server returns 401. `null` for other failure statuses.
  final String? wwwAuthenticate;

  @override
  String toString() =>
      'McpHttpTransportError(status=$statusCode): ${body.isEmpty ? '<empty>' : body}';
}

// ─── Auth resolution ───────────────────────────────────────────────────────

/// Resolves the bearer token for an MCP server, honouring:
///   • [McpBearerAuth] — literal token from config, falling back to
///     `mcp:<server-id>:bearer` in the credential store.
///   • [McpOAuthAuth] — current `oauth_access` field from the credential
///     store (populated by `glue mcp auth login <server>`).
///   • [McpNoAuth] — null (no Authorization header).
///
/// Returns `null` when no token is available. Callers send no header
/// in that case; the server may 401, which the pool surfaces as
/// `McpServerAuthRequiredEvent` so the user knows to log in.
String? resolveMcpBearerToken(
  McpAuthSpec auth,
  CredentialStore credentials,
  String serverId,
) {
  return switch (auth) {
    McpBearerAuth(:final token) =>
      token ?? credentials.getField('mcp:$serverId', 'bearer'),
    McpOAuthAuth() => credentials.getField('mcp:$serverId', 'oauth_access'),
    McpNoAuth() => null,
  };
}
