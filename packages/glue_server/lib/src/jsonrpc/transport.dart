/// Transport for line-delimited JSON-RPC over stream pairs (stdio,
/// websocket bytes, in-memory pipes).
///
/// The transport is deliberately abstract — it accepts a `Stream<List<int>>`
/// for input and an `IOSink`-shaped object for output. That lets the
/// server be tested with in-memory streams and run for real on stdin/stdout.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue_server/src/jsonrpc/codec.dart';
import 'package:glue_server/src/jsonrpc/messages.dart';

/// A bidirectional JSON-RPC transport. Each `incoming` element is one
/// decoded message; `send` enqueues one message for the peer.
abstract class JsonRpcTransport {
  Stream<JsonRpcMessage> get incoming;

  /// Send a message to the peer. May be called concurrently with
  /// [incoming]; implementations serialize as needed.
  void send(JsonRpcMessage message);

  /// Closes the outbound side. The transport is expected to drain
  /// pending writes before closing.
  Future<void> close();
}

/// Line-delimited JSON-RPC transport. Each newline-terminated chunk on
/// the inbound stream is one JSON-RPC message; each outbound message is
/// written as one line followed by `\n`.
///
/// This is the default framing for ACP and MCP over stdio.
class LineDelimitedTransport implements JsonRpcTransport {
  LineDelimitedTransport({
    required Stream<List<int>> input,
    required this.output,
  }) : _input = input;

  final Stream<List<int>> _input;
  final Sink<List<int>> output;

  StreamController<JsonRpcMessage>? _controller;
  StreamSubscription<String>? _sub;

  @override
  Stream<JsonRpcMessage> get incoming {
    final existing = _controller;
    if (existing != null) return existing.stream;

    final controller = StreamController<JsonRpcMessage>();
    _controller = controller;

    final lines =
        _input.transform(utf8.decoder).transform(const LineSplitter());

    _sub = lines.listen(
      (line) {
        if (line.isEmpty) return;
        controller.add(decodeJsonRpcString(line));
      },
      onError: controller.addError,
      onDone: controller.close,
      cancelOnError: false,
    );

    return controller.stream;
  }

  @override
  void send(JsonRpcMessage message) {
    final encoded = encodeJsonRpcString(message);
    output.add(utf8.encode('$encoded\n'));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
    output.close();
  }
}
