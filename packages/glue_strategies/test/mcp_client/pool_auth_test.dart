import 'dart:async';
import 'dart:io';

import 'package:glue_server/glue_server.dart';
import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/mcp_client/client.dart';
import 'package:glue_strategies/src/mcp_client/config.dart';
import 'package:glue_strategies/src/mcp_client/connection_state.dart';
import 'package:glue_strategies/src/mcp_client/oauth.dart';
import 'package:glue_strategies/src/mcp_client/pool.dart';
import 'package:glue_strategies/src/mcp_client/transport/http_sse.dart';
import 'package:test/test.dart';

import 'in_memory_transport.dart';

CredentialStore _store() => CredentialStore(
  path: '${Directory.systemTemp.createTempSync('pool_auth_').path}/creds.json',
  env: const {},
);

McpClientFactory _factoryThatAlways401({
  String wwwAuth = 'Bearer resource_metadata="https://meta.example/x"',
}) {
  return (spec, creds) async {
    final transport = InMemoryMcpTransport();
    final client = McpClient(transport: transport);
    // Push the 401 after a microtask so the initialize request has been
    // sent and is waiting on the pending map.
    scheduleMicrotask(() {
      transport.pushError(
        McpHttpTransportError(
          statusCode: 401,
          body: '',
          wwwAuthenticate: wwwAuth,
        ),
      );
    });
    return client;
  };
}

void main() {
  group('pool auth', () {
    test(
      '401 with no refresh token → AuthRequired + AwaitingAuth + no retry',
      () async {
        final creds = _store();
        final pool = McpClientPool(
          config: McpConfig(
            servers: [
              McpHttpServerSpec(
                id: 'foo',
                url: Uri.parse('https://foo.example/mcp'),
                auth: const McpNoAuth(),
              ),
            ],
          ),
          credentials: creds,
          clientFactory: _factoryThatAlways401(),
        );

        final events = <McpPoolEvent>[];
        pool.events.listen(events.add);
        pool.connectAll();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final authEvents = events.whereType<McpPoolServerAuthRequiredEvent>();
        expect(authEvents, hasLength(1));
        expect(authEvents.single.serverId, 'foo');
        expect(
          authEvents.single.wwwAuthenticate,
          contains('resource_metadata'),
        );
        expect(pool.server('foo')!.state, isA<McpAwaitingAuth>());

        // Wait through what would have been a retry window.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(
          pool.server('foo')!.state,
          isA<McpAwaitingAuth>(),
          reason: 'should not have armed retry timer',
        );
        await pool.close();
      },
    );

    test('401 with valid refresh token → silent refresh → Connected', () async {
      final creds = _store();
      creds.setFields('mcp:foo', {
        'oauth_refresh': 'good-refresh',
        'oauth_client_id': 'CID',
      });

      var attemptCount = 0;
      final pool = McpClientPool(
        config: McpConfig(
          servers: [
            McpHttpServerSpec(
              id: 'foo',
              url: Uri.parse('https://foo.example/mcp'),
              auth: const McpOAuthAuth(),
              authorizationServer: Uri.parse('https://auth.foo.example'),
            ),
          ],
        ),
        credentials: creds,
        clientFactory: (spec, c) async {
          attemptCount++;
          final thisAttempt = attemptCount;
          final transport = InMemoryMcpTransport(
            respond: (msg) async {
              // Second attempt: respond happily to initialize / tools/list.
              if (thisAttempt == 2 && msg is JsonRpcRequest) {
                if (msg.method == 'initialize') {
                  return [
                    JsonRpcResponse(
                      id: msg.id,
                      result: {
                        'protocolVersion': '2025-03-26',
                        'serverInfo': {'name': 'foo', 'version': '1'},
                        'capabilities': const <String, dynamic>{},
                      },
                    ),
                  ];
                } else if (msg.method == 'tools/list') {
                  return [
                    JsonRpcResponse(id: msg.id, result: {'tools': const []}),
                  ];
                }
              }
              return const [];
            },
          );
          final client = McpClient(transport: transport);
          if (thisAttempt == 1) {
            scheduleMicrotask(() {
              transport.pushError(
                const McpHttpTransportError(statusCode: 401, body: ''),
              );
            });
          }
          return client;
        },
        refreshGrant: (serverId, refreshToken) async {
          expect(serverId, 'foo');
          expect(refreshToken, 'good-refresh');
          return const OAuthTokens(
            accessToken: 'fresh-AT',
            refreshToken: 'fresh-RT',
          );
        },
      );

      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(pool.server('foo')!.state, isA<McpConnected>());
      final fields = creds.getFields('mcp:foo');
      expect(fields['oauth_access'], 'fresh-AT');
      expect(fields['oauth_refresh'], 'fresh-RT');
      await pool.close();
    });

    test('401 + refresh failure → invalidate tokens + AuthRequired', () async {
      final creds = _store();
      creds.setFields('mcp:foo', {
        'oauth_refresh': 'bad-refresh',
        'oauth_client_id': 'CID',
        'oauth_client_secret': 'SEC',
      });
      final pool = McpClientPool(
        config: McpConfig(
          servers: [
            McpHttpServerSpec(
              id: 'foo',
              url: Uri.parse('https://foo.example/mcp'),
              auth: const McpOAuthAuth(),
              authorizationServer: Uri.parse('https://auth.foo.example'),
            ),
          ],
        ),
        credentials: creds,
        clientFactory: _factoryThatAlways401(),
        refreshGrant: (sid, rt) async =>
            throw const OAuthFlowException('rotted'),
      );

      final events = <McpPoolEvent>[];
      pool.events.listen(events.add);
      pool.connectAll();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final fields = creds.getFields('mcp:foo');
      expect(fields['oauth_refresh'], isNull);
      expect(
        fields['oauth_client_id'],
        'CID',
        reason: 'tokens invalidation must keep client_id',
      );
      expect(fields['oauth_client_secret'], 'SEC');
      expect(pool.server('foo')!.state, isA<McpAwaitingAuth>());
      expect(events.whereType<McpPoolServerAuthRequiredEvent>(), hasLength(1));
      await pool.close();
    });
  });
}
