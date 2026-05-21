/// In-memory [JsonRpcTransport] for tests.
///
/// Models a fake MCP server: tests provide a `respond` callback that
/// receives each outgoing message and returns the messages the "server"
/// should reply with. Notifications can also be pushed at any time via
/// [pushFromServer].
library;

import 'dart:async';

import 'package:glue_server/glue_server.dart';

class InMemoryMcpTransport implements JsonRpcTransport {
  InMemoryMcpTransport({this.respond});

  /// Called for each outgoing message. Returns the messages to surface
  /// to the client as "received from server". May be empty (for
  /// notifications) or asynchronous.
  final Future<List<JsonRpcMessage>> Function(JsonRpcMessage outgoing)? respond;

  final _incoming = StreamController<JsonRpcMessage>.broadcast();
  final outgoing = <JsonRpcMessage>[];
  bool _closed = false;

  @override
  Stream<JsonRpcMessage> get incoming => _incoming.stream;

  @override
  void send(JsonRpcMessage message) {
    if (_closed) return;
    outgoing.add(message);
    final r = respond;
    if (r == null) return;
    // Schedule the response on the microtask queue so it arrives after
    // the caller has finished its `transport.send(...)` line — matches
    // real network timing.
    () async {
      final reply = await r(message);
      for (final m in reply) {
        if (_closed) return;
        _incoming.add(m);
      }
    }();
  }

  /// Push a message from the "server" side at an arbitrary time
  /// (e.g. a notification).
  void pushFromServer(JsonRpcMessage message) {
    if (_closed) return;
    _incoming.add(message);
  }

  /// Push an error into the incoming stream — simulates a transport-level
  /// failure like a 401 response surfacing as `McpHttpTransportError`.
  void pushError(Object error) {
    if (_closed) return;
    _incoming.addError(error);
  }

  /// Simulate a transport drop. All current and future pending calls
  /// on the client side should fail with `retryable: true`.
  void simulateDrop() {
    if (_closed) return;
    _incoming.close();
    _closed = true;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _incoming.close();
  }
}
