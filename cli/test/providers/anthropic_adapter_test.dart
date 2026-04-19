import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/llm/anthropic_client.dart';
import 'package:glue/src/providers/anthropic_adapter.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicAdapter', () {
    test('adapterId is "anthropic"', () {
      expect(AnthropicAdapter().adapterId, 'anthropic');
    });

    test('createClient returns AnthropicClient with the resolved apiKey', () {
      final adapter = AnthropicAdapter();
      const provider = ProviderDef(
        id: 'anthropic',
        name: 'Anthropic',
        adapter: 'anthropic',
        auth: AuthSpec(kind: AuthKind.env, envVar: 'ANTHROPIC_API_KEY'),
        models: {},
      );
      const model = ModelDef(id: 'claude-sonnet-4.6', name: 'Claude Sonnet');
      final client = adapter.createClient(
        provider: const ResolvedProvider(def: provider, apiKey: 'sk-test'),
        model: const ResolvedModel(def: model, provider: provider),
        systemPrompt: 'you are a helpful assistant',
      );
      expect(client, isA<AnthropicClient>());
      expect((client as AnthropicClient).apiKey, 'sk-test');
      expect(client.model, 'claude-sonnet-4.6');
      expect(client.systemPrompt, 'you are a helpful assistant');
    });

    test('validate returns missingCredential when apiKey is null', () {
      final adapter = AnthropicAdapter();
      const provider = ProviderDef(
        id: 'anthropic',
        name: 'Anthropic',
        adapter: 'anthropic',
        auth: AuthSpec(kind: AuthKind.env, envVar: 'ANTHROPIC_API_KEY'),
        models: {},
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: null)),
        ProviderHealth.missingCredential,
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: 'sk')),
        ProviderHealth.ok,
      );
    });

    test('createClient honors custom base URL from ProviderDef', () {
      final adapter = AnthropicAdapter();
      const provider = ProviderDef(
        id: 'anthropic-proxy',
        name: 'Proxy',
        adapter: 'anthropic',
        baseUrl: 'https://proxy.example.com',
        auth: AuthSpec(kind: AuthKind.none),
        models: {},
      );
      const model = ModelDef(id: 'claude', name: 'Claude');
      final client = adapter.createClient(
        provider: const ResolvedProvider(def: provider, apiKey: 'sk'),
        model: const ResolvedModel(def: model, provider: provider),
        systemPrompt: '',
      );
      expect(client, isA<AnthropicClient>());
    });
  });
}
