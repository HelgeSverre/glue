import 'dart:async';
import 'dart:convert';

import 'package:glue_server/glue_server.dart';
import 'package:test/test.dart';

class _MemorySink implements Sink<List<int>> {
  final List<int> buffer = [];
  bool closed = false;

  @override
  void add(List<int> data) => buffer.addAll(data);

  @override
  void close() => closed = true;

  String get utf8 => const Utf8Decoder().convert(buffer);
}

void main() {
  group('LineDelimitedTransport', () {
    test('decodes one line per JSON-RPC message', () async {
      final controller = StreamController<List<int>>();
      final transport = LineDelimitedTransport(
        input: controller.stream,
        output: _MemorySink(),
      );

      final received = <JsonRpcMessage>[];
      // ignore: cancel_subscriptions — closes when the source stream completes.
      final sub = transport.incoming.listen(received.add);
      addTearDown(sub.cancel);

      controller.add(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"a"}\n'));
      controller.add(utf8.encode('{"jsonrpc":"2.0","method":"n"}\n'));
      await controller.close();
      await sub.asFuture<void>();

      expect(received, hasLength(2));
      expect(received[0], isA<JsonRpcRequest>());
      expect(received[1], isA<JsonRpcNotification>());
    });

    test('skips empty lines without producing parse errors', () async {
      final controller = StreamController<List<int>>();
      final transport = LineDelimitedTransport(
        input: controller.stream,
        output: _MemorySink(),
      );

      final received = <JsonRpcMessage>[];
      final sub = transport.incoming.listen(received.add);
      addTearDown(sub.cancel);

      controller.add(utf8.encode('\n\n'));
      controller.add(utf8.encode('{"jsonrpc":"2.0","id":1,"method":"m"}\n'));
      await controller.close();
      await sub.asFuture<void>();

      expect(received, hasLength(1));
      expect(received.single, isA<JsonRpcRequest>());
    });

    test('write encodes with trailing newline', () {
      final sink = _MemorySink();
      addTearDown(sink.close);
      final transport = LineDelimitedTransport(
        input: const Stream.empty(),
        output: sink,
      );

      transport.send(const JsonRpcResponse(id: 1, result: 'ok'));

      expect(sink.utf8, '{"jsonrpc":"2.0","id":1,"result":"ok"}\n');
    });
  });
}
