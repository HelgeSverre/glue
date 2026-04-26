import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:test/test.dart';

class _FakeClient implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) {
    throw UnimplementedError();
  }
}

class _FakeAdapter extends ProviderAdapter {
  @override
  String get adapterId => 'fake';

  @override
  ProviderHealth validate(ResolvedProvider provider) => provider.apiKey == null
      ? ProviderHealth.missingCredential
      : ProviderHealth.ok;

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) =>
      _FakeClient();
}

ProviderDef _provider({
  String id = 'fake',
  String adapter = 'fake',
  String? compatibility,
  AuthSpec auth = const AuthSpec(kind: AuthKind.none),
}) =>
    ProviderDef(
      id: id,
      name: id,
      adapter: adapter,
      compatibility: compatibility,
      auth: auth,
      models: const {},
    );

void main() {
  group('ResolvedProvider', () {
    test('compatibility defaults to adapter id when omitted', () {
      final p = _provider(adapter: 'openai');
      final r = ResolvedProvider(def: p, apiKey: null);
      expect(r.compatibility, 'openai');
    });

    test('compatibility returns explicit value when set', () {
      final p = _provider(adapter: 'openai', compatibility: 'groq');
      final r = ResolvedProvider(def: p, apiKey: null);
      expect(r.compatibility, 'groq');
    });

    test('withApiKey overlays apiKey AND syncs credentials.api_key', () {
      final p = _provider(adapter: 'openai');
      final original = ResolvedProvider(
        def: p,
        apiKey: 'old-key',
        credentials: const {'api_key': 'old-key', 'extra': 'preserved'},
      );
      final updated = original.withApiKey('new-key');
      expect(updated.apiKey, 'new-key');
      expect(updated.credentials['api_key'], 'new-key',
          reason: 'credentials map should be in sync with apiKey');
      expect(updated.credentials['extra'], 'preserved',
          reason: 'unrelated credential fields must survive the overlay');
    });

    test('withApiKey(null) clears both apiKey and credentials.api_key', () {
      final p = _provider(adapter: 'openai');
      final original = ResolvedProvider(
        def: p,
        apiKey: 'old',
        credentials: const {'api_key': 'old'},
      );
      final cleared = original.withApiKey(null);
      expect(cleared.apiKey, isNull);
      expect(cleared.credentials.containsKey('api_key'), isFalse);
    });
  });

  group('AdapterRegistry', () {
    test('lookup returns the adapter matching adapterId', () {
      final registry = AdapterRegistry([_FakeAdapter()]);
      expect(registry.lookup('fake'), isA<_FakeAdapter>());
    });

    test('lookup returns null for unknown adapter', () {
      final registry = AdapterRegistry([_FakeAdapter()]);
      expect(registry.lookup('missing'), isNull);
    });

    test('registered lists adapter ids', () {
      final registry = AdapterRegistry([_FakeAdapter()]);
      expect(registry.registered, ['fake']);
    });

    test('duplicate adapter ids throw at construction', () {
      expect(
        () => AdapterRegistry([_FakeAdapter(), _FakeAdapter()]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ProviderAdapter', () {
    test('default discoverModels returns empty list (opt-in only)', () async {
      final adapter = _FakeAdapter();
      final resolved = ResolvedProvider(def: _provider(), apiKey: null);
      expect(await adapter.discoverModels(resolved), isEmpty);
    });

    test('validate reports missing credentials', () {
      final adapter = _FakeAdapter();
      final p = _provider(
        auth: const AuthSpec(kind: AuthKind.apiKey, envVar: 'X'),
      );
      expect(
        adapter.validate(ResolvedProvider(def: p, apiKey: null)),
        ProviderHealth.missingCredential,
      );
      expect(
        adapter.validate(ResolvedProvider(def: p, apiKey: 'sk-123')),
        ProviderHealth.ok,
      );
    });
  });
}
