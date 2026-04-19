import 'package:glue/src/catalog/catalog_loader.dart';
import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:test/test.dart';

ModelCatalog _catalog(String yaml) => parseCatalogYaml(yaml);

const _bundled = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: anthropic/claude-sonnet-4.6
  small_model: openai/gpt-5.4-mini
capabilities:
  chat: Text chat.
  tools: Tool calling.
providers:
  anthropic:
    name: Anthropic
    adapter: anthropic
    enabled: true
    auth:
      api_key: env:ANTHROPIC_API_KEY
    models:
      claude-sonnet-4.6:
        name: Claude Sonnet 4.6
        recommended: true
        default: true
        capabilities: [chat, tools]
        context_window: 200000
  openai:
    name: OpenAI
    adapter: openai
    enabled: true
    auth:
      api_key: env:OPENAI_API_KEY
    models:
      gpt-5.4:
        name: GPT-5.4
        recommended: true
        default: true
        capabilities: [chat, tools]
''';

void main() {
  group('loadCatalog', () {
    test('returns bundled as-is with no overrides', () {
      final bundled = _catalog(_bundled);
      final merged = loadCatalog(bundled: bundled);
      expect(merged.providers.keys, {'anthropic', 'openai'});
      expect(merged.defaults.model, 'anthropic/claude-sonnet-4.6');
    });

    test('local override adds a new provider', () {
      final bundled = _catalog(_bundled);
      final overrides = _catalog('''
version: 1
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers:
  my-local:
    name: My Local
    adapter: openai
    compatibility: vllm
    base_url: http://localhost:9000/v1
    auth:
      api_key: none
    models:
      my-model:
        name: My Model
''');

      final merged = loadCatalog(bundled: bundled, localOverrides: overrides);
      expect(merged.providers.keys,
          containsAll(['anthropic', 'openai', 'my-local']));
      expect(merged.providers['my-local']!.compatibility, 'vllm');
    });

    test('local override replaces an existing provider', () {
      final bundled = _catalog(_bundled);
      final overrides = _catalog('''
version: 1
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers:
  openai:
    name: OpenAI Custom
    adapter: openai
    base_url: https://proxy.example/v1
    auth:
      api_key: env:MY_CUSTOM_KEY
    models:
      gpt-5.4:
        name: GPT-5.4 (proxied)
''');

      final merged = loadCatalog(bundled: bundled, localOverrides: overrides);
      final openai = merged.providers['openai']!;
      expect(openai.name, 'OpenAI Custom');
      expect(openai.baseUrl, 'https://proxy.example/v1');
      expect(openai.auth.envVar, 'MY_CUSTOM_KEY');
      expect(openai.models['gpt-5.4']!.name, 'GPT-5.4 (proxied)');
    });

    test('local override updates defaults', () {
      final bundled = _catalog(_bundled);
      final overrides = _catalog('''
version: 1
defaults:
  model: openai/gpt-5.4
capabilities: {}
providers: {}
''');

      final merged = loadCatalog(bundled: bundled, localOverrides: overrides);
      expect(merged.defaults.model, 'openai/gpt-5.4');
    });

    test('cached remote merges between bundled and local (local wins)', () {
      final bundled = _catalog(_bundled);
      final remote = _catalog('''
version: 1
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers:
  openai:
    name: OpenAI From Remote
    adapter: openai
    auth:
      api_key: none
    models: {}
''');
      final overrides = _catalog('''
version: 1
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers:
  openai:
    name: OpenAI Local
    adapter: openai
    auth:
      api_key: env:OPENAI_API_KEY
    models: {}
''');

      final merged = loadCatalog(
        bundled: bundled,
        cachedRemote: remote,
        localOverrides: overrides,
      );
      expect(merged.providers['openai']!.name, 'OpenAI Local');
    });

    test('capabilities map is merged (union)', () {
      final bundled = _catalog(_bundled);
      final overrides = _catalog('''
version: 1
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities:
  vision: Image input.
providers: {}
''');
      final merged = loadCatalog(bundled: bundled, localOverrides: overrides);
      expect(
          merged.capabilities.keys, containsAll(['chat', 'tools', 'vision']));
    });
  });
}
