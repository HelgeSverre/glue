import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('parseWwwAuthenticate', () {
    test('extracts resource_metadata and scope from Bearer challenge', () {
      final challenge = parseWwwAuthenticate(
        'Bearer resource_metadata="https://example.com/.well-known/oauth-protected-resource", '
        'scope="read write"',
      );
      expect(challenge?.scheme, 'Bearer');
      expect(challenge?.resourceMetadata,
          Uri.parse('https://example.com/.well-known/oauth-protected-resource'));
      expect(challenge?.scope, ['read', 'write']);
    });

    test('handles quoted commas inside a parameter value', () {
      final challenge = parseWwwAuthenticate(
        'Bearer error="invalid_token", error_description="token expired, please refresh"',
      );
      expect(challenge?.scheme, 'Bearer');
      expect(challenge?.parameters['error_description'],
          'token expired, please refresh');
    });

    test('returns null when scheme is not Bearer', () {
      expect(parseWwwAuthenticate('Basic realm="foo"'), isNull);
    });

    test('returns null on empty/missing header', () {
      expect(parseWwwAuthenticate(null), isNull);
      expect(parseWwwAuthenticate(''), isNull);
    });

    test('handles missing resource_metadata gracefully', () {
      final challenge = parseWwwAuthenticate('Bearer realm="api"');
      expect(challenge?.scheme, 'Bearer');
      expect(challenge?.resourceMetadata, isNull);
      expect(challenge?.scope, isEmpty);
    });
  });

  group('discoverProtectedResourceMetadata', () {
    test('uses URL from WWW-Authenticate when supplied', () async {
      final client = _FakeHttpClient({
        Uri.parse('https://meta.example/oauth-protected-resource'): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
      });
      final meta = await discoverProtectedResourceMetadata(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        resourceMetadataUrl:
            Uri.parse('https://meta.example/oauth-protected-resource'),
        httpClient: client,
      );
      expect(meta.authorizationServers.first,
          Uri.parse('https://auth.example'));
      expect(meta.resource, Uri.parse('https://mcp.example'));
    });

    test('falls back to path-suffixed well-known when no hint', () async {
      final client = _FakeHttpClient({
        Uri.parse(
                'https://mcp.example/.well-known/oauth-protected-resource/mcp'):
            const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
      });
      final meta = await discoverProtectedResourceMetadata(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        httpClient: client,
      );
      expect(meta.authorizationServers.first,
          Uri.parse('https://auth.example'));
    });

    test('falls back to root well-known on 404 of path variant', () async {
      final client = _FakeHttpClient({
        Uri.parse(
                'https://mcp.example/.well-known/oauth-protected-resource/mcp'):
            const _Response(404, ''),
        Uri.parse('https://mcp.example/.well-known/oauth-protected-resource'):
            const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
      });
      final meta = await discoverProtectedResourceMetadata(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        httpClient: client,
      );
      expect(meta.authorizationServers.first,
          Uri.parse('https://auth.example'));
    });

    test('throws when no metadata can be located', () async {
      final client = _FakeHttpClient(const {});
      expect(
        () => discoverProtectedResourceMetadata(
          serverUrl: Uri.parse('https://mcp.example/mcp'),
          httpClient: client,
        ),
        throwsA(isA<OAuthDiscoveryException>()),
      );
    });
  });
}

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.responses);
  final Map<Uri, _Response> responses;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final res = responses[request.url];
    if (res == null) {
      return http.StreamedResponse(
        Stream.value(<int>[]),
        404,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream.value(res.body.codeUnits),
      res.statusCode,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}
