import 'package:glue_server/glue_server.dart';
import 'package:test/test.dart';

void main() {
  group('encodeJsonRpc', () {
    test('encodes a request', () {
      const msg = JsonRpcRequest(
        id: 1,
        method: 'session/new',
        params: {'cwd': '/tmp/p'},
      );
      expect(encodeJsonRpc(msg), {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'session/new',
        'params': {'cwd': '/tmp/p'},
      });
    });

    test('omits params when null', () {
      const msg = JsonRpcRequest(id: 1, method: 'initialize');
      expect(encodeJsonRpc(msg).containsKey('params'), isFalse);
    });

    test('encodes a notification (no id)', () {
      const msg = JsonRpcNotification(
        method: 'session/cancel',
        params: {'sessionId': 's1'},
      );
      final wire = encodeJsonRpc(msg);
      expect(wire.containsKey('id'), isFalse);
      expect(wire['method'], 'session/cancel');
    });

    test('encodes a response', () {
      const msg = JsonRpcResponse(id: 1, result: {'sessionId': 's1'});
      expect(encodeJsonRpc(msg)['result'], {'sessionId': 's1'});
    });

    test('encodes an error with optional data', () {
      const msg = JsonRpcError(
        id: 1,
        code: JsonRpcErrorCode.invalidParams,
        message: 'missing cwd',
        data: 'expected string',
      );
      final wire = encodeJsonRpc(msg);
      expect(wire['error'], {
        'code': -32602,
        'message': 'missing cwd',
        'data': 'expected string',
      });
    });
  });

  group('decodeJsonRpc round-trips', () {
    test('request', () {
      final back = decodeJsonRpc(encodeJsonRpc(
        const JsonRpcRequest(id: 7, method: 'm', params: {'k': 'v'}),
      ));
      expect(back, isA<JsonRpcRequest>());
      back as JsonRpcRequest;
      expect(back.id, 7);
      expect(back.method, 'm');
      expect(back.params, {'k': 'v'});
    });

    test('notification', () {
      final back = decodeJsonRpc(encodeJsonRpc(
        const JsonRpcNotification(method: 'n'),
      ));
      expect(back, isA<JsonRpcNotification>());
    });

    test('response', () {
      final back = decodeJsonRpc(encodeJsonRpc(
        const JsonRpcResponse(id: 1, result: 42),
      ));
      expect(back, isA<JsonRpcResponse>());
      back as JsonRpcResponse;
      expect(back.result, 42);
    });

    test('error', () {
      final back = decodeJsonRpc(encodeJsonRpc(
        const JsonRpcError(id: 1, code: -32601, message: 'no such method'),
      ));
      expect(back, isA<JsonRpcError>());
      back as JsonRpcError;
      expect(back.code, -32601);
    });
  });

  group('decodeJsonRpcString', () {
    test('returns parseError on malformed JSON', () {
      final back = decodeJsonRpcString('not json');
      expect(back, isA<JsonRpcError>());
      back as JsonRpcError;
      expect(back.code, JsonRpcErrorCode.parseError);
    });

    test('returns parseError on non-object top-level', () {
      final back = decodeJsonRpcString('[1,2,3]');
      expect(back, isA<JsonRpcError>());
      back as JsonRpcError;
      expect(back.code, JsonRpcErrorCode.parseError);
    });

    test('rejects messages without jsonrpc:"2.0"', () {
      final back = decodeJsonRpcString('{"id":1,"method":"m"}');
      expect(back, isA<JsonRpcError>());
      back as JsonRpcError;
      expect(back.code, JsonRpcErrorCode.invalidRequest);
    });
  });
}
