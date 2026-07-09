/// HTTP host for ACP over WebSocket.
///
/// Binds an HTTP server to a port, accepts WebSocket upgrades on
/// configurable paths, and spawns one [AcpServer] per connection. All
/// connections share the same [AcpServerDelegate] (so harness state
/// like `ServiceLocator` initialization is reused), but each
/// connection has its own per-connection session map inside that
/// delegate's implementation.
///
/// Multi-tenancy isolation between *connections* is the delegate's
/// responsibility — the host just hands each WS the JSON-RPC peer
/// adapter.
library;

import 'dart:async';
import 'dart:io';

import 'package:glue_server/src/acp/server.dart';
import 'package:glue_server/src/jsonrpc/websocket_transport.dart';

/// Binds an [HttpServer], handles WebSocket upgrades on [path], and
/// runs an [AcpServer] for each connection.
class AcpHttpHost {
  AcpHttpHost({
    required this.delegateFactory,
    this.config = const AcpServerConfig(),
    this.path = '/acp',
    this.bearerToken,
  });

  /// Called once per inbound connection — produces the delegate the
  /// connection's [AcpServer] will use. Returning a fresh delegate
  /// per connection isolates session state between WS clients;
  /// returning a shared singleton lets connections see each other's
  /// sessions (use only when that's the explicit design).
  final AcpServerDelegate Function() delegateFactory;

  final AcpServerConfig config;

  /// HTTP path that accepts the WebSocket upgrade. Other paths return
  /// 404. `*` accepts any path.
  final String path;

  /// When non-null, every WebSocket upgrade must present this token in
  /// either an `Authorization: Bearer <token>` header or a `?token=…`
  /// query parameter. Required for non-loopback binds.
  final String? bearerToken;

  HttpServer? _server;
  final Set<_Connection> _connections = {};
  final _connectionsClosed = StreamController<void>.broadcast();

  /// The bound port (after [start]). Useful for tests that pass `0`.
  int? get port => _server?.port;

  /// Number of currently-active WebSocket connections. Useful for
  /// tests + observability.
  int get activeConnections => _connections.length;

  /// Stream that fires every time a connection closes — useful for
  /// tests that want to await teardown.
  Stream<void> get onConnectionClosed => _connectionsClosed.stream;

  /// Bind the HTTP server. Returns the bound port. Pass [port]=0 to
  /// let the OS pick.
  Future<int> start({InternetAddress? address, int port = 3000}) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _server = server;
    _acceptLoop(server);
    return server.port;
  }

  Future<void> _acceptLoop(HttpServer server) async {
    try {
      await for (final request in server) {
        // A single misbehaving request (client resetting mid-response, a
        // malformed upgrade, …) must never throw out of the `await for` —
        // that would silently stop the host from accepting ALL future
        // connections. Isolate every request in its own try/catch.
        try {
          await _handleRequest(request);
        } on Object catch (e) {
          stderr.writeln('AcpHttpHost: request handling failed: $e');
        }
      }
    } on Object catch (e) {
      // The server socket itself errored; there is nothing left to accept.
      stderr.writeln('AcpHttpHost: accept loop terminated: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (path != '*' && request.uri.path != path) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found');
      await request.response.close();
      return;
    }
    // Reject any request that carries an `Origin` header. Browsers attach
    // Origin to every WebSocket handshake; legitimate native / editor ACP
    // clients do not send one. Refusing Origin-bearing upgrades blocks the
    // DNS-rebinding / drive-by attack where a website the user visits opens
    // ws://127.0.0.1:<port>/acp, drives the agent, and auto-approves its own
    // tool requests — a defence that holds even on a token-less loopback bind.
    if (request.headers.value('origin') != null) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('cross-origin WebSocket connections are not allowed');
      await request.response.close();
      return;
    }
    if (!_authorized(request)) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.add(HttpHeaders.wwwAuthenticateHeader, 'Bearer realm="acp"')
        ..write('unauthorized');
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('expected WebSocket upgrade');
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    // Fire-and-forget: _runConnection guards its own body so a connection's
    // serve loop failing can never escape as an isolate-fatal async error.
    unawaited(_runConnection(socket));
  }

  Future<void> _runConnection(WebSocket socket) async {
    final transport = WebSocketTransport(socket);
    _Connection? connection;
    try {
      final delegate = delegateFactory();
      final acp = AcpServer(
        transport: transport,
        delegate: delegate,
        config: config,
      );
      connection = _Connection(transport: transport, server: acp);
      _connections.add(connection);
      await acp.serve();
    } on Object catch (e) {
      // One connection's failure (delegate construction, serve loop error,
      // transport error) must not take down the host or leak as an unhandled
      // async error. Log and let the finally tear the socket down.
      stderr.writeln('AcpHttpHost: connection failed: $e');
    } finally {
      await transport.close();
      if (connection != null) _connections.remove(connection);
      if (!_connectionsClosed.isClosed) _connectionsClosed.add(null);
    }
  }

  /// Close the host. Existing connections are forcibly torn down.
  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    await server.close(force: true);
    _server = null;
    for (final c in _connections.toList()) {
      await c.transport.close();
    }
    _connections.clear();
    if (!_connectionsClosed.isClosed) await _connectionsClosed.close();
  }

  bool _authorized(HttpRequest request) {
    final expected = bearerToken;
    if (expected == null) return true;
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null) {
      const prefix = 'Bearer ';
      if (auth.startsWith(prefix) &&
          _constantTimeEquals(auth.substring(prefix.length), expected)) {
        return true;
      }
    }
    final query = request.uri.queryParameters['token'];
    if (query != null && _constantTimeEquals(query, expected)) {
      return true;
    }
    return false;
  }
}

/// Constant-time string compare to avoid leaking the token byte-by-byte
/// through timing. Cheap enough that we always run it.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

class _Connection {
  _Connection({required this.transport, required this.server});
  final WebSocketTransport transport;
  final AcpServer server;
}
