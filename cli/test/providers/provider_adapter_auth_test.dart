/// Tests the default `beginInteractiveAuth` + `isConnected` impls on
/// [ProviderAdapter] for api-key and none kinds.
library;

import 'dart:io';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:test/test.dart';

class _FakeClient implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) =>
      throw UnimplementedError();
}

class _FakeAdapter extends ProviderAdapter {
  @override
  String get adapterId => 'fake';

  @override
  ProviderHealth validate(ResolvedProvider provider) => ProviderHealth.ok;

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) =>
      _FakeClient();
}

Directory _scratch() =>
    Directory.systemTemp.createTempSync('glue_auth_hooks_test_');

ProviderDef _provider({
  required AuthSpec auth,
  String id = 'fake',
}) =>
    ProviderDef(
      id: id,
      name: id,
      adapter: 'fake',
      auth: auth,
      models: const {},
    );

void main() {
  group('ProviderAdapter.beginInteractiveAuth default impl', () {
    test('AuthKind.none returns null', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final provider = _provider(auth: const AuthSpec(kind: AuthKind.none));
      final flow = await _FakeAdapter().beginInteractiveAuth(
        provider: provider,
        store: store,
      );
      expect(flow, isNull);
    });

    test('AuthKind.apiKey returns an ApiKeyFlow with envPresent when set',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: {'ANTHROPIC_API_KEY': 'sk-env'},
      );
      final provider = _provider(
        auth: const AuthSpec(
          kind: AuthKind.apiKey,
          envVar: 'ANTHROPIC_API_KEY',
          helpUrl: 'https://console.example.com',
        ),
      );
      final flow = await _FakeAdapter().beginInteractiveAuth(
        provider: provider,
        store: store,
      );
      expect(flow, isA<ApiKeyFlow>());
      final apiKey = flow! as ApiKeyFlow;
      expect(apiKey.envVar, 'ANTHROPIC_API_KEY');
      expect(apiKey.envPresent, 'sk-env');
      expect(apiKey.helpUrl, contains('example.com'));
    });

    test('AuthKind.apiKey returns ApiKeyFlow with envPresent null when unset',
        () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final provider = _provider(
        auth: const AuthSpec(kind: AuthKind.apiKey, envVar: 'MISSING'),
      );
      final flow = await _FakeAdapter().beginInteractiveAuth(
        provider: provider,
        store: store,
      ) as ApiKeyFlow;
      expect(flow.envPresent, isNull);
    });

    test('AuthKind.oauth on default impl throws UnimplementedError', () async {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final provider = _provider(auth: const AuthSpec(kind: AuthKind.oauth));
      expect(
        () async => _FakeAdapter().beginInteractiveAuth(
          provider: provider,
          store: store,
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('ProviderAdapter.isConnected default impl', () {
    test('none is always connected', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final p = _provider(auth: const AuthSpec(kind: AuthKind.none));
      expect(_FakeAdapter().isConnected(p, store), isTrue);
    });

    test('apiKey is connected when env set', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: {'ANTHROPIC_API_KEY': 'sk-env'},
      );
      final p = _provider(
        auth:
            const AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
      );
      expect(_FakeAdapter().isConnected(p, store), isTrue);
    });

    test('apiKey is not connected when neither env nor stored', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final p = _provider(
        auth:
            const AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
      );
      expect(_FakeAdapter().isConnected(p, store), isFalse);
    });

    test('oauth is false on default impl (adapters must override)', () {
      final dir = _scratch();
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CredentialStore(
        path: '${dir.path}/c.json',
        env: const {},
      );
      final p = _provider(auth: const AuthSpec(kind: AuthKind.oauth));
      expect(_FakeAdapter().isConnected(p, store), isFalse);
    });
  });
}
