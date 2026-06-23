import 'dart:async';
import 'dart:convert';

import 'package:glue_strategies/glue_strategies.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _CapturedRequest {
  _CapturedRequest(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final FutureOr<http.Response> Function(http.BaseRequest request, String body)
  _handler;
  final requests = <_CapturedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request
        ? await request.finalize().bytesToString()
        : '';
    requests.add(
      _CapturedRequest(request.method, request.url, request.headers, body),
    );
    final response = await _handler(request, body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  group('HttpSessionBrowserProvider shared plumbing', () {
    test('apiKey guard throws a labelled error on provision', () {
      expect(
        SteelProvider(apiKey: null).provision,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Steel API key not configured',
          ),
        ),
      );
    });

    test('Browserbase guard uses its custom not-configured reason', () {
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: null).provision,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Browserbase API key or project ID not configured',
          ),
        ),
      );
    });

    test('non-2xx response raises a labelled API error', () {
      final client = _FakeHttpClient(
        (request, body) => http.Response('nope', 503),
      );
      expect(
        SteelProvider(apiKey: 'k', client: client).provision,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Steel API error 503: nope',
          ),
        ),
      );
    });

    test('Steel provisions and issues a DELETE close request', () async {
      final client = _FakeHttpClient((request, body) {
        if (request.method == 'POST') {
          expect(request.url.toString(), 'https://api.steel.dev/v1/sessions');
          expect(request.headers['Authorization'], 'Bearer test-key');
          expect(jsonDecode(body), {'projectId': 'default'});
          return http.Response(
            jsonEncode({
              'id': 'sess-1',
              'websocketUrl': 'wss://steel.example/cdp',
              'viewerUrl': 'https://steel.example/view/sess-1',
            }),
            200,
          );
        }
        expect(request.method, 'DELETE');
        expect(
          request.url.toString(),
          'https://api.steel.dev/v1/sessions/sess-1',
        );
        expect(request.headers['Authorization'], 'Bearer test-key');
        return http.Response('{}', 200);
      });

      final endpoint = await SteelProvider(
        apiKey: 'test-key',
        client: client,
      ).provision();

      expect(endpoint.cdpWsUrl, 'wss://steel.example/cdp');
      expect(endpoint.backendName, 'steel');
      expect(endpoint.viewUrl, 'https://steel.example/view/sess-1');

      await endpoint.close();
      expect(client.requests.map((r) => r.method), ['POST', 'DELETE']);
    });

    test('Browserbase provisions and issues a POST stop request', () async {
      final client = _FakeHttpClient((request, body) {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/sessions')) {
          expect(request.headers['X-BB-API-Key'], 'bb-key');
          expect(jsonDecode(body), {'projectId': 'proj-1'});
          return http.Response(jsonEncode({'id': 'bb-sess'}), 200);
        }
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://www.browserbase.com/v1/sessions/bb-sess/stop',
        );
        expect(request.headers['X-BB-API-Key'], 'bb-key');
        return http.Response('{}', 200);
      });

      final endpoint = await BrowserbaseProvider(
        apiKey: 'bb-key',
        projectId: 'proj-1',
        client: client,
      ).provision();

      expect(
        endpoint.cdpWsUrl,
        'wss://connect.browserbase.com?apiKey=bb-key&sessionId=bb-sess',
      );
      expect(endpoint.viewUrl, 'https://www.browserbase.com/sessions/bb-sess');

      await endpoint.close();
      expect(client.requests.map((r) => r.method), ['POST', 'POST']);
    });
  });
}
