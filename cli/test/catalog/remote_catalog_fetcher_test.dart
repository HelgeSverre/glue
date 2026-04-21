import 'dart:async';
import 'dart:io';

import 'package:glue/src/catalog/remote_catalog_fetcher.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _resp(int status, String body,
    {Map<String, String>? headers}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(body.codeUnits),
    status,
    headers: {'content-type': 'application/yaml', ...?headers},
  );
}

void main() {
  group('RemoteCatalogFetcher', () {
    test('returns FetchUpdated on 200 with sanitized body', () async {
      const payload = '''
version: 1
providers:
  x:
    name: X
    adapter: openai
    auth:
      api_key: SECRET
    models: {}
''';
      final fetcher = RemoteCatalogFetcher(
        client: _FakeClient((req) async => _resp(200, payload)),
      );
      final result =
          await fetcher.fetch(Uri.parse('https://example.com/c.yaml'));

      expect(result, isA<FetchUpdated>());
      final updated = result as FetchUpdated;
      expect(updated.yaml, isNot(contains('SECRET')));
    });

    test('returns FetchNotModified on 304', () async {
      final fetcher = RemoteCatalogFetcher(
        client: _FakeClient((req) async => _resp(304, '')),
      );
      final result =
          await fetcher.fetch(Uri.parse('https://example.com/c.yaml'));
      expect(result, isA<FetchNotModified>());
    });

    test('returns FetchFailed on 4xx/5xx (does not throw)', () async {
      final fetcher = RemoteCatalogFetcher(
        client: _FakeClient((req) async => _resp(503, 'boom')),
      );
      final result =
          await fetcher.fetch(Uri.parse('https://example.com/c.yaml'));
      expect(result, isA<FetchFailed>());
      expect((result as FetchFailed).reason, contains('503'));
    });

    test('returns FetchFailed on network error (does not throw)', () async {
      final fetcher = RemoteCatalogFetcher(
        client: _FakeClient((req) async {
          throw const SocketException('host unreachable');
        }),
      );
      final result =
          await fetcher.fetch(Uri.parse('https://example.com/c.yaml'));
      expect(result, isA<FetchFailed>());
    });

    test('sends If-Modified-Since header when provided', () async {
      http.BaseRequest? captured;
      final fetcher = RemoteCatalogFetcher(
        client: _FakeClient((req) async {
          captured = req;
          return _resp(304, '');
        }),
      );
      await fetcher.fetch(
        Uri.parse('https://example.com/c.yaml'),
        ifModifiedSince: 'Sun, 06 Nov 1994 08:49:37 GMT',
      );
      expect(
        captured?.headers['If-Modified-Since'],
        'Sun, 06 Nov 1994 08:49:37 GMT',
      );
    });

    test('respects timeout (returns FetchFailed, not a hang)', () async {
      final fetcher = RemoteCatalogFetcher(
        client: _FakeClient((req) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return _resp(200, 'irrelevant');
        }),
      );
      final result = await fetcher.fetch(
        Uri.parse('https://example.com/c.yaml'),
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, isA<FetchFailed>());
      expect((result as FetchFailed).reason, contains('timeout'));
    });
  });
}
