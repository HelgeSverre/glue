/// CopilotProvider integration tests — fake http drives device flow end-to-end.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/copilot_provider.dart';
import 'package:glue/src/providers/copilot_token_manager.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _Handler {
  _Handler(this.fn);

  final Future<http.StreamedResponse> Function(http.BaseRequest) fn;
}

class _RoutedHttp extends http.BaseClient {
  _RoutedHttp(this.route);

  final _Handler Function(http.BaseRequest) route;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      route(request).fn(request);
}

http.StreamedResponse _json(int status, Map<String, dynamic> body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_copilot_provider_test_');

const _copilotProvider = ProviderDef(
  id: 'copilot',
  name: 'GitHub Copilot',
  adapter: 'copilot',
  baseUrl: 'https://api.githubcopilot.com',
  auth: AuthSpec(kind: AuthKind.oauth),
  models: {},
);

void main() {
  group('CopilotProvider.beginInteractiveAuth', () {
    test('returns a DeviceCodeFlow whose progress stream drives token exchange',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );

      var pollCalls = 0;
      final client = _RoutedHttp((req) {
        final url = req.url.toString();
        if (url.contains('login/device/code')) {
          return _Handler((_) async => _json(200, {
                'device_code': 'DEV-CODE',
                'user_code': 'ABCD-1234',
                'verification_uri': 'https://github.com/login/device',
                'expires_in': 900,
                'interval': 0, // tests poll without delay
              }));
        }
        if (url.contains('login/oauth/access_token')) {
          pollCalls++;
          return _Handler((_) async {
            if (pollCalls == 1) {
              return _json(200, {'error': 'authorization_pending'});
            }
            return _json(200, {
              'access_token': 'gho_approved',
              'token_type': 'bearer',
            });
          });
        }
        if (url.contains('copilot_internal/v2/token')) {
          return _Handler((_) async => _json(200, {
                'token': 'tid=session',
                'expires_at': DateTime.now()
                        .add(const Duration(minutes: 30))
                        .millisecondsSinceEpoch ~/
                    1000,
              }));
        }
        return _Handler(
          (req) async => http.StreamedResponse(
            const Stream.empty(),
            404,
            headers: const {},
          ),
        );
      });

      final adapter = CopilotProvider(client: client);
      final flow = await adapter.beginInteractiveAuth(
        provider: _copilotProvider,
        store: store,
      );
      expect(flow, isA<DeviceCodeFlow>());
      final device = flow! as DeviceCodeFlow;
      expect(device.userCode, 'ABCD-1234');
      expect(device.verificationUri, contains('github.com/login/device'));

      // Drain the progress stream.
      final events = <AuthFlowProgress>[];
      await for (final ev in device.progress) {
        events.add(ev);
      }

      expect(events.whereType<AuthFlowPolling>(), isNotEmpty);
      expect(events.last, isA<AuthFlowSucceeded>());
      final success = events.last as AuthFlowSucceeded;
      expect(success.fields[CopilotFields.githubToken], 'gho_approved');
      expect(success.fields[CopilotFields.copilotToken], 'tid=session');
      expect(success.fields[CopilotFields.expiresAt], isNotEmpty);

      // Also stored.
      expect(
          store.getField('copilot', CopilotFields.githubToken), 'gho_approved');
    });

    test('emits AuthFlowFailed on access_denied', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );

      final client = _RoutedHttp((req) {
        final url = req.url.toString();
        if (url.contains('login/device/code')) {
          return _Handler((_) async => _json(200, {
                'device_code': 'dc',
                'user_code': 'XXXX',
                'verification_uri': 'https://example',
                'expires_in': 10,
                'interval': 0,
              }));
        }
        if (url.contains('login/oauth/access_token')) {
          return _Handler((_) async => _json(200, {'error': 'access_denied'}));
        }
        return _Handler(
          (req) async => http.StreamedResponse(const Stream.empty(), 404,
              headers: const {}),
        );
      });

      final adapter = CopilotProvider(client: client);
      final flow = await adapter.beginInteractiveAuth(
        provider: _copilotProvider,
        store: store,
      ) as DeviceCodeFlow;

      final last = await flow.progress.last;
      expect(last, isA<AuthFlowFailed>());
      expect((last as AuthFlowFailed).reason.toLowerCase(), contains('denied'));
      expect(store.getField('copilot', CopilotFields.githubToken), isNull);
    });
  });

  group('CopilotProvider.isConnected', () {
    test('true when github_token is stored', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      store.setFields('copilot', {CopilotFields.githubToken: 'gho_x'});
      expect(
        CopilotProvider().isConnected(_copilotProvider, store),
        isTrue,
      );
    });

    test('false when not stored', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      expect(
        CopilotProvider().isConnected(_copilotProvider, store),
        isFalse,
      );
    });
  });

  group('CopilotProvider.createClient', () {
    test('returns an LlmClient (integration happens in stream call)', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      store.setFields('copilot', {
        CopilotFields.githubToken: 'gho_x',
        CopilotFields.copilotToken: 'tid=valid',
        CopilotFields.expiresAt: DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      });
      final adapter = CopilotProvider(credentialStore: store);
      final client = adapter.createClient(
        provider: const ResolvedProvider(
          def: _copilotProvider,
          credentials: {'github_token': 'gho_x'},
        ),
        model: const ResolvedModel(
          def: ModelDef(id: 'gpt-4.1', name: 'GPT-4.1'),
          provider: _copilotProvider,
        ),
        systemPrompt: 'test',
      );
      expect(client, isA<LlmClient>());
      expect(client, isA<CopilotProvider>());
    });

    test('throws StateError without a CredentialStore', () {
      final adapter = CopilotProvider();
      expect(
        () => adapter.createClient(
          provider: const ResolvedProvider(
            def: _copilotProvider,
            credentials: {},
          ),
          model: const ResolvedModel(
            def: ModelDef(id: 'gpt-4.1', name: 'GPT-4.1'),
            provider: _copilotProvider,
          ),
          systemPrompt: '',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CopilotProvider.stream uses cached token', () {
    test('reads a non-expired copilot token from the store without refreshing',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      store.setFields('copilot', {
        CopilotFields.githubToken: 'gho_valid',
        CopilotFields.copilotToken: 'tid=fresh',
        CopilotFields.expiresAt: DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 20))
            .toIso8601String(),
      });

      // Capture inference request header + verify no github exchange call.
      var exchangeCalls = 0;
      String? authHeader;
      String? integrationIdHeader;
      final client = _RoutedHttp((req) {
        final url = req.url.toString();
        if (url.contains('copilot_internal/v2/token')) {
          exchangeCalls++;
          return _Handler((_) async => _json(200, {
                'token': 'tid=new',
                'expires_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }));
        }
        if (url.contains('chat/completions')) {
          authHeader = req.headers['Authorization'];
          integrationIdHeader = req.headers['Copilot-Integration-Id'];
          // Return a minimal finished SSE stream.
          final sse = 'data: ${jsonEncode({
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'stop'}
                ],
                'usage': {'prompt_tokens': 1, 'completion_tokens': 1},
              })}\n\ndata: [DONE]\n\n';
          return _Handler((_) async => http.StreamedResponse(
                Stream<List<int>>.value(utf8.encode(sse)),
                200,
                headers: {'content-type': 'text/event-stream'},
              ));
        }
        return _Handler((_) async => http.StreamedResponse(
              const Stream.empty(),
              404,
              headers: const {},
            ));
      });

      final adapter = CopilotProvider(
        client: client,
        credentialStore: store,
      );
      final per = adapter.createClient(
        provider: const ResolvedProvider(
          def: _copilotProvider,
          credentials: {'github_token': 'gho_valid'},
        ),
        model: const ResolvedModel(
          def: ModelDef(id: 'gpt-4.1', name: 'GPT-4.1'),
          provider: _copilotProvider,
        ),
        systemPrompt: '',
      );

      await per.stream([Message.user('hi')]).drain<void>();

      expect(exchangeCalls, 0, reason: 'cached token should not re-exchange');
      expect(authHeader, 'Bearer tid=fresh');
      expect(integrationIdHeader, 'vscode-chat');
    });

    test('expired cached token triggers a refresh via github exchange',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      store.setFields('copilot', {
        CopilotFields.githubToken: 'gho_valid',
        CopilotFields.copilotToken: 'tid=stale',
        CopilotFields.expiresAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      });

      var exchangeCalls = 0;
      String? authHeader;
      final client = _RoutedHttp((req) {
        final url = req.url.toString();
        if (url.contains('copilot_internal/v2/token')) {
          exchangeCalls++;
          return _Handler((_) async => _json(200, {
                'token': 'tid=refreshed',
                'expires_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }));
        }
        if (url.contains('chat/completions')) {
          authHeader = req.headers['Authorization'];
          final sse = 'data: ${jsonEncode({
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'stop'}
                ],
              })}\n\ndata: [DONE]\n\n';
          return _Handler((_) async => http.StreamedResponse(
                Stream<List<int>>.value(utf8.encode(sse)),
                200,
                headers: {'content-type': 'text/event-stream'},
              ));
        }
        return _Handler((_) async => http.StreamedResponse(
              const Stream.empty(),
              404,
              headers: const {},
            ));
      });

      final adapter = CopilotProvider(
        client: client,
        credentialStore: store,
      );
      final per = adapter.createClient(
        provider: const ResolvedProvider(
          def: _copilotProvider,
          credentials: {'github_token': 'gho_valid'},
        ),
        model: const ResolvedModel(
          def: ModelDef(id: 'gpt-4.1', name: 'GPT-4.1'),
          provider: _copilotProvider,
        ),
        systemPrompt: '',
      );

      await per.stream([Message.user('hi')]).drain<void>();

      expect(exchangeCalls, 1,
          reason: 'expired token should trigger a refresh');
      expect(authHeader, 'Bearer tid=refreshed');

      // Store should have the refreshed token persisted.
      expect(store.getField('copilot', CopilotFields.copilotToken),
          'tid=refreshed');
    });
  });
}
