import 'dart:async';
import 'dart:convert';

import 'package:glue/src/web/browser/providers/anchor_provider.dart';
import 'package:glue/src/web/browser/providers/browserbase_provider.dart';
import 'package:glue/src/web/browser/providers/browserless_provider.dart';
import 'package:glue/src/web/browser/providers/hyperbrowser_provider.dart';
import 'package:glue/src/web/browser/providers/steel_provider.dart';
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
    final body =
        request is http.Request ? await request.finalize().bytesToString() : '';
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
  group('SteelProvider', () {
    test('has correct name', () {
      final provider = SteelProvider(apiKey: 'test-key');
      expect(provider.name, 'steel');
    });

    test('is configured when API key is set', () {
      final provider = SteelProvider(apiKey: 'test-key');
      expect(provider.isConfigured, isTrue);
    });

    test('is not configured without API key', () {
      final provider = SteelProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });
  });

  group('BrowserbaseProvider', () {
    test('has correct name', () {
      final provider = BrowserbaseProvider(
        apiKey: 'key',
        projectId: 'proj',
      );
      expect(provider.name, 'browserbase');
    });

    test('requires both API key and project ID', () {
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: null).isConfigured,
        isFalse,
      );
      expect(
        BrowserbaseProvider(apiKey: null, projectId: 'proj').isConfigured,
        isFalse,
      );
      expect(
        BrowserbaseProvider(apiKey: 'key', projectId: 'proj').isConfigured,
        isTrue,
      );
    });
  });

  group('BrowserlessProvider', () {
    test('has correct name', () {
      final provider = BrowserlessProvider(
        apiKey: 'key',
        baseUrl: 'https://chrome.example.com',
      );
      expect(provider.name, 'browserless');
    });

    test('is configured with API key', () {
      final provider = BrowserlessProvider(
        apiKey: 'key',
        baseUrl: 'https://chrome.example.com',
      );
      expect(provider.isConfigured, isTrue);
    });

    test('builds WebSocket URL from base URL', () {
      final provider = BrowserlessProvider(
        apiKey: 'my-key',
        baseUrl: 'https://chrome.browserless.io',
      );
      final wsUrl = provider.buildWsUrl();
      expect(wsUrl, contains('wss://'));
      expect(wsUrl, contains('my-key'));
    });
  });

  group('AnchorProvider', () {
    test('has correct name', () {
      final provider = AnchorProvider(apiKey: 'key');
      expect(provider.name, 'anchor');
    });

    test('is configured with API key', () {
      expect(AnchorProvider(apiKey: 'key').isConfigured, isTrue);
      expect(AnchorProvider(apiKey: null).isConfigured, isFalse);
    });

    test('provisions CDP endpoint and closes session', () async {
      final client = _FakeHttpClient((request, body) {
        if (request.method == 'POST') {
          expect(request.url.toString(),
              'https://api.anchorbrowser.io/v1/sessions');
          expect(request.headers['anchor-api-key'], 'test-key');
          expect(request.headers['Content-Type'], 'application/json');
          expect(body, '{}');
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'session-123',
                'cdp_url': 'wss://anchor.example/cdp',
                'live_view_url': 'https://anchor.example/live/session-123',
              },
            }),
            200,
          );
        }

        expect(request.method, 'DELETE');
        expect(request.url.toString(),
            'https://api.anchorbrowser.io/v1/sessions/session-123');
        expect(request.headers['anchor-api-key'], 'test-key');
        return http.Response(
          jsonEncode({
            'data': {'status': 'ok'},
          }),
          200,
        );
      });

      final provider = AnchorProvider(apiKey: 'test-key', client: client);
      final endpoint = await provider.provision();

      expect(endpoint.cdpWsUrl, 'wss://anchor.example/cdp');
      expect(endpoint.backendName, 'anchor');
      expect(endpoint.viewUrl, 'https://anchor.example/live/session-123');

      await endpoint.close();

      expect(client.requests.map((r) => r.method), ['POST', 'DELETE']);
    });
  });

  group('HyperbrowserProvider', () {
    test('has correct name', () {
      final provider = HyperbrowserProvider(apiKey: 'key');
      expect(provider.name, 'hyperbrowser');
    });

    test('is configured with API key', () {
      expect(HyperbrowserProvider(apiKey: 'key').isConfigured, isTrue);
      expect(HyperbrowserProvider(apiKey: null).isConfigured, isFalse);
      expect(HyperbrowserProvider(apiKey: '').isConfigured, isFalse);
    });

    test('provisions CDP endpoint and closes session', () async {
      final client = _FakeHttpClient((request, body) {
        if (request.method == 'POST') {
          expect(request.url.toString(),
              'https://api.hyperbrowser.ai/api/session');
          expect(request.headers['x-api-key'], 'test-key');
          expect(request.headers['Content-Type'], 'application/json');
          expect(body, '{}');
          return http.Response(
            jsonEncode({
              'id': 'session-abc',
              'wsEndpoint': 'wss://hyperbrowser.example/cdp',
              'liveUrl': 'https://hyperbrowser.example/live/session-abc',
            }),
            200,
          );
        }

        expect(request.method, 'PUT');
        expect(request.url.toString(),
            'https://api.hyperbrowser.ai/api/session/session-abc/stop');
        expect(request.headers['x-api-key'], 'test-key');
        return http.Response('{}', 200);
      });

      final provider = HyperbrowserProvider(apiKey: 'test-key', client: client);
      final endpoint = await provider.provision();

      expect(endpoint.cdpWsUrl, 'wss://hyperbrowser.example/cdp');
      expect(endpoint.backendName, 'hyperbrowser');
      expect(endpoint.viewUrl, 'https://hyperbrowser.example/live/session-abc');

      await endpoint.close();

      expect(client.requests.map((r) => r.method), ['POST', 'PUT']);
    });
  });
}
