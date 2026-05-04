/// WebSocket-backed implementation of [JsonRpcTransport].
///
/// Each WebSocket message frame is one JSON-RPC message — no
/// line-delimited framing needed (the WS layer already preserves
/// message boundaries). Outbound `JsonRpcMessage`s are serialized as
/// JSON text frames; inbound text frames are parsed; binary frames
/// are silently dropped (we don't speak any binary JSON-RPC variant).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_server/src/jsonrpc/codec.dart';
import 'package:glue_server/src/jsonrpc/messages.dart';
import 'package:glue_server/src/jsonrpc/transport.dart';

class WebSocketTransport implements JsonRpcTransport {
  WebSocketTransport(this._socket);

  final WebSocket _socket;

  StreamController<JsonRpcMessage>? _controller;
  StreamSubscription<dynamic>? _sub;

  @override
  Stream<JsonRpcMessage> get incoming {
    final existing = _controller;
    if (existing != null) return existing.stream;
    final controller = StreamController<JsonRpcMessage>();
    _controller = controller;

    _sub = _socket.listen(
      (frame) {
        // We accept text frames as JSON; binary frames are coerced to
        // utf-8 strings — most senders use text but a few wrap the
        // same JSON payload in a binary frame.
        final String payload;
        if (frame is String) {
          payload = frame;
        } else if (frame is List<int>) {
          try {
            payload = utf8.decode(frame);
          } on FormatException catch (e) {
            controller.add(JsonRpcError(
              id: null,
              code: JsonRpcErrorCode.parseError,
              message: 'binary frame is not valid UTF-8: ${e.message}',
            ));
            return;
          }
        } else {
          // Unknown frame type; ignore.
          return;
        }
        controller.add(decodeJsonRpcString(payload));
      },
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: false,
    );
    return controller.stream;
  }

  @override
  void send(JsonRpcMessage message) {
    if (_socket.readyState != WebSocket.open) return;
    _socket.add(encodeJsonRpcString(message));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
    if (_socket.readyState != WebSocket.closed) {
      await _socket.close();
    }
  }
}
