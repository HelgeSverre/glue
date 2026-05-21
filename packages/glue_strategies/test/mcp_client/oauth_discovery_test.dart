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
      expect(
        challenge?.resourceMetadata,
        Uri.parse('https://example.com/.well-known/oauth-protected-resource'),
      );
      expect(challenge?.scope, ['read', 'write']);
    });

    test('handles quoted commas inside a parameter value', () {
      final challenge = parseWwwAuthenticate(
        'Bearer error="invalid_token", error_description="token expired, please refresh"',
      );
      expect(challenge?.scheme, 'Bearer');
      expect(
        challenge?.parameters['error_description'],
        'token expired, please refresh',
      );
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
        Uri.parse(
          'https://meta.example/oauth-protected-resource',
        ): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
      });
      final meta = await discoverProtectedResourceMetadata(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        resourceMetadataUrl: Uri.parse(
          'https://meta.example/oauth-protected-resource',
        ),
        httpClient: client,
      );
      expect(
        meta.authorizationServers.first,
        Uri.parse('https://auth.example'),
      );
      expect(meta.resource, Uri.parse('https://mcp.example'));
    });

    test('falls back to path-suffixed well-known when no hint', () async {
      final client = _FakeHttpClient({
        Uri.parse(
          'https://mcp.example/.well-known/oauth-protected-resource/mcp',
        ): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
      });
      final meta = await discoverProtectedResourceMetadata(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        httpClient: client,
      );
      expect(
        meta.authorizationServers.first,
        Uri.parse('https://auth.example'),
      );
    });

    test('falls back to root well-known on 404 of path variant', () async {
      final client = _FakeHttpClient({
        Uri.parse(
          'https://mcp.example/.well-known/oauth-protected-resource/mcp',
        ): const _Response(
          404,
          '',
        ),
        Uri.parse(
          'https://mcp.example/.well-known/oauth-protected-resource',
        ): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
      });
      final meta = await discoverProtectedResourceMetadata(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        httpClient: client,
      );
      expect(
        meta.authorizationServers.first,
        Uri.parse('https://auth.example'),
      );
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

  group('discoverAuthorizationServerMetadata', () {
    test('returns endpoints from RFC 8414 metadata', () async {
      final client = _FakeHttpClient({
        Uri.parse(
          'https://auth.example/.well-known/oauth-authorization-server',
        ): const _Response(
          200,
          '{'
          '"issuer":"https://auth.example",'
          '"authorization_endpoint":"https://auth.example/authorize",'
          '"token_endpoint":"https://auth.example/token",'
          '"registration_endpoint":"https://auth.example/register"'
          '}',
        ),
      });
      final endpoints = await discoverAuthorizationServerMetadata(
        authServer: Uri.parse('https://auth.example'),
        httpClient: client,
      );
      expect(endpoints.tokenEndpoint, Uri.parse('https://auth.example/token'));
      expect(
        endpoints.registrationEndpoint,
        Uri.parse('https://auth.example/register'),
      );
    });

    test('rejects metadata whose issuer does not match URL', () async {
      final client = _FakeHttpClient({
        Uri.parse(
          'https://auth.example/.well-known/oauth-authorization-server',
        ): const _Response(
          200,
          '{'
          '"issuer":"https://attacker.example",'
          '"authorization_endpoint":"https://attacker.example/authorize",'
          '"token_endpoint":"https://attacker.example/token"'
          '}',
        ),
      });
      expect(
        () => discoverAuthorizationServerMetadata(
          authServer: Uri.parse('https://auth.example'),
          httpClient: client,
        ),
        throwsA(isA<OAuthDiscoveryException>()),
      );
    });

    test('falls back to OIDC discovery path on 404', () async {
      final client = _FakeHttpClient({
        Uri.parse(
          'https://auth.example/.well-known/oauth-authorization-server',
        ): const _Response(
          404,
          '',
        ),
        Uri.parse(
          'https://auth.example/.well-known/openid-configuration',
        ): const _Response(
          200,
          '{'
          '"issuer":"https://auth.example",'
          '"authorization_endpoint":"https://auth.example/authorize",'
          '"token_endpoint":"https://auth.example/token"'
          '}',
        ),
      });
      final endpoints = await discoverAuthorizationServerMetadata(
        authServer: Uri.parse('https://auth.example'),
        httpClient: client,
      );
      expect(endpoints.tokenEndpoint, Uri.parse('https://auth.example/token'));
    });
  });

  group('discoverMcpAuth', () {
    test('end-to-end: header → protected metadata → auth server', () async {
      final client = _FakeHttpClient({
        Uri.parse('https://meta.example/protected'): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
        Uri.parse(
          'https://auth.example/.well-known/oauth-authorization-server',
        ): const _Response(
          200,
          '{'
          '"issuer":"https://auth.example",'
          '"authorization_endpoint":"https://auth.example/authorize",'
          '"token_endpoint":"https://auth.example/token"'
          '}',
        ),
      });
      final discovery = await discoverMcpAuth(
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        wwwAuthenticate:
            'Bearer resource_metadata="https://meta.example/protected", scope="read"',
        httpClient: client,
      );
      expect(
        discovery.endpoints.tokenEndpoint,
        Uri.parse('https://auth.example/token'),
      );
      expect(
        discovery.resourceMetadataUrl,
        Uri.parse('https://meta.example/protected'),
      );
      expect(discovery.authorizationServer, Uri.parse('https://auth.example'));
      expect(discovery.scopes, ['read']); // header wins over metadata
    });

    test('falls back to legacy direct discovery when no RFC 9728', () async {
      final client = _FakeHttpClient({
        Uri.parse(
          'https://mcp.example/.well-known/oauth-authorization-server',
        ): const _Response(
          200,
          '{'
          '"issuer":"https://mcp.example",'
          '"authorization_endpoint":"https://mcp.example/authorize",'
          '"token_endpoint":"https://mcp.example/token"'
          '}',
        ),
      });
      final discovery = await discoverMcpAuth(
        serverUrl: Uri.parse('https://mcp.example'),
        httpClient: client,
      );
      expect(
        discovery.endpoints.tokenEndpoint,
        Uri.parse('https://mcp.example/token'),
      );
      expect(discovery.resourceMetadataUrl, isNull);
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
