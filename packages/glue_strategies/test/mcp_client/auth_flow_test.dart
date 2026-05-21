import 'dart:io';

import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/mcp_client/auth_flow.dart';
import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

CredentialStore _store() => CredentialStore(
      path: '${Directory.systemTemp.createTempSync('auth_flow_').path}/creds.json',
      env: const {},
    );

void main() {
  group('McpAuthFlowRunner', () {
    test('emits Discovering → Registering → AwaitingCallback → Success when DCR needed',
        () async {
      final fakeHttp = _FakeHttpClient({
        Uri.parse('https://meta.example/protected'): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
        Uri.parse(
                'https://auth.example/.well-known/oauth-authorization-server'):
            const _Response(
          200,
          '{'
          '"issuer":"https://auth.example",'
          '"authorization_endpoint":"https://auth.example/authorize",'
          '"token_endpoint":"https://auth.example/token",'
          '"registration_endpoint":"https://auth.example/register"'
          '}',
        ),
        Uri.parse('https://auth.example/register'): const _Response(
          200,
          '{"client_id":"abc-123"}',
        ),
      });

      final runner = McpAuthFlowRunner(
        serverId: 'foo',
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        credentials: _store(),
        wwwAuthenticate:
            'Bearer resource_metadata="https://meta.example/protected"',
        httpClient: fakeHttp,
        codeFlow: ({
          required endpoints,
          required client,
          required scopes,
          required onAuthUrl,
          httpClient,
        }) async {
          onAuthUrl('https://auth.example/authorize?state=fake&code_challenge=x');
          return const OAuthTokens(
            accessToken: 'AT',
            refreshToken: 'RT',
          );
        },
      );

      final states = <McpAuthFlowState>[];
      runner.states.listen(states.add);
      final terminal = await runner.run();

      expect(terminal, isA<McpAuthFlowSuccess>());
      final types = states.map((s) => s.runtimeType).toList();
      expect(types, contains(McpAuthFlowDiscovering));
      expect(types, contains(McpAuthFlowRegistering));
      expect(types, contains(McpAuthFlowAwaitingCallback));
      expect(types.last, McpAuthFlowSuccess);
    });

    test('skips Registering when client_id is already stored', () async {
      final store = _store();
      store.setFields('mcp:foo', {'oauth_client_id': 'pre-registered'});

      final fakeHttp = _FakeHttpClient({
        Uri.parse('https://meta.example/protected'): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
        Uri.parse(
                'https://auth.example/.well-known/oauth-authorization-server'):
            const _Response(
          200,
          '{'
          '"issuer":"https://auth.example",'
          '"authorization_endpoint":"https://auth.example/authorize",'
          '"token_endpoint":"https://auth.example/token"'
          '}',
        ),
      });

      final runner = McpAuthFlowRunner(
        serverId: 'foo',
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        credentials: store,
        wwwAuthenticate:
            'Bearer resource_metadata="https://meta.example/protected"',
        httpClient: fakeHttp,
        codeFlow: ({
          required endpoints,
          required client,
          required scopes,
          required onAuthUrl,
          httpClient,
        }) async {
          onAuthUrl('https://auth.example/authorize?state=fake');
          return const OAuthTokens(accessToken: 'AT');
        },
      );

      final states = <McpAuthFlowState>[];
      runner.states.listen(states.add);
      await runner.run();

      final types = states.map((s) => s.runtimeType).toList();
      expect(types, isNot(contains(McpAuthFlowRegistering)));
      expect(types.last, McpAuthFlowSuccess);
    });

    test('errors when no registration_endpoint and no stored client_id', () async {
      final fakeHttp = _FakeHttpClient({
        Uri.parse('https://meta.example/protected'): const _Response(
          200,
          '{"resource":"https://mcp.example","authorization_servers":["https://auth.example"]}',
        ),
        Uri.parse(
                'https://auth.example/.well-known/oauth-authorization-server'):
            const _Response(
          200,
          '{'
          '"issuer":"https://auth.example",'
          '"authorization_endpoint":"https://auth.example/authorize",'
          '"token_endpoint":"https://auth.example/token"'
          '}',
        ),
      });

      final runner = McpAuthFlowRunner(
        serverId: 'foo',
        serverUrl: Uri.parse('https://mcp.example/mcp'),
        credentials: _store(),
        wwwAuthenticate:
            'Bearer resource_metadata="https://meta.example/protected"',
        httpClient: fakeHttp,
      );

      final terminal = await runner.run();
      expect(terminal, isA<McpAuthFlowError>());
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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = responses[request.url];
    if (res == null) {
      return http.StreamedResponse(Stream.value(<int>[]), 404, request: request);
    }
    return http.StreamedResponse(
      Stream.value(res.body.codeUnits),
      res.statusCode,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}
