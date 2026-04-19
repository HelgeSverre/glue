import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('parseCatalogYaml', () {
    test('parses a minimal catalog', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: anthropic/claude-sonnet-4.6
  small_model: openai/gpt-5.4-mini
capabilities: {}
providers: {}
''';

      final catalog = parseCatalogYaml(yaml);

      expect(catalog.version, 1);
      expect(catalog.defaults.model, 'anthropic/claude-sonnet-4.6');
      expect(catalog.defaults.smallModel, 'openai/gpt-5.4-mini');
      expect(catalog.providers, isEmpty);
    });

    test('parses provider with one model', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: anthropic/claude-sonnet-4.6
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
        speed: standard
        cost: high
''';

      final catalog = parseCatalogYaml(yaml);

      expect(catalog.providers.keys, ['anthropic']);
      final anthropic = catalog.providers['anthropic']!;
      expect(anthropic.id, 'anthropic');
      expect(anthropic.name, 'Anthropic');
      expect(anthropic.adapter, 'anthropic');
      expect(anthropic.enabled, isTrue);
      expect(anthropic.auth.kind, AuthKind.apiKey);
      expect(anthropic.auth.envVar, 'ANTHROPIC_API_KEY');

      expect(anthropic.models.keys, ['claude-sonnet-4.6']);
      final model = anthropic.models['claude-sonnet-4.6']!;
      expect(model.id, 'claude-sonnet-4.6');
      expect(model.name, 'Claude Sonnet 4.6');
      expect(model.recommended, isTrue);
      expect(model.isDefault, isTrue);
      expect(model.capabilities, {'chat', 'tools'});
      expect(model.contextWindow, 200000);
      expect(model.speed, 'standard');
      expect(model.cost, 'high');
    });

    test('defaults for optional fields', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers:
  openai:
    name: OpenAI
    adapter: openai
    auth:
      api_key: env:OPENAI_API_KEY
    models:
      gpt-x:
        name: GPT X
''';

      final catalog = parseCatalogYaml(yaml);
      final provider = catalog.providers['openai']!;
      expect(provider.enabled, isTrue, reason: 'enabled defaults to true');
      expect(provider.baseUrl, isNull);
      expect(provider.compatibility, isNull);
      expect(provider.requestHeaders, isEmpty);

      final model = provider.models['gpt-x']!;
      expect(model.recommended, isFalse);
      expect(model.isDefault, isFalse);
      expect(model.capabilities, isEmpty);
      expect(model.contextWindow, isNull);
      expect(model.apiId, 'gpt-x', reason: 'api_id defaults to the YAML key');
    });

    test('api_id overrides the catalog key for the wire identifier', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: groq/gpt-oss-120b
capabilities: {}
providers:
  groq:
    name: Groq
    adapter: openai
    auth:
      api_key: env:GROQ_API_KEY
    models:
      gpt-oss-120b:
        name: GPT-OSS 120B
        api_id: openai/gpt-oss-120b
''';

      final catalog = parseCatalogYaml(yaml);
      final model = catalog.providers['groq']!.models['gpt-oss-120b']!;
      expect(model.id, 'gpt-oss-120b');
      expect(model.apiId, 'openai/gpt-oss-120b');
    });

    test('parses auth api_key: none as AuthKind.none', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: ollama/llama3.2
capabilities: {}
providers:
  ollama:
    name: Ollama
    adapter: openai
    compatibility: ollama
    base_url: http://localhost:11434/v1
    auth:
      api_key: none
    models:
      llama3.2:
        name: Llama 3.2
''';

      final catalog = parseCatalogYaml(yaml);
      final ollama = catalog.providers['ollama']!;
      expect(ollama.auth.kind, AuthKind.none);
      expect(ollama.auth.envVar, isNull);
      expect(ollama.baseUrl, 'http://localhost:11434/v1');
      expect(ollama.compatibility, 'ollama');
    });

    test('ignores unknown top-level fields (forward-compat)', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers: {}
future_field_we_dont_know_about: true
another:
  nested: value
''';

      expect(() => parseCatalogYaml(yaml), returnsNormally);
    });

    test('throws on missing version', () {
      const yaml = '''
defaults:
  model: anthropic/claude-sonnet-4.6
capabilities: {}
providers: {}
''';

      expect(
        () => parseCatalogYaml(yaml),
        throwsA(isA<CatalogParseException>()),
      );
    });

    test('throws on missing defaults.model', () {
      const yaml = '''
version: 1
defaults:
  small_model: openai/gpt-5.4-mini
capabilities: {}
providers: {}
''';

      expect(
        () => parseCatalogYaml(yaml),
        throwsA(isA<CatalogParseException>()),
      );
    });

    test('parses explicit kind: oauth with help_url', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: copilot/gpt-4.1
capabilities: {}
providers:
  copilot:
    name: GitHub Copilot
    adapter: copilot
    base_url: https://api.githubcopilot.com
    auth:
      kind: oauth
      help_url: https://github.com/login/device
    models:
      gpt-4.1:
        name: GPT-4.1 (via Copilot)
''';

      final catalog = parseCatalogYaml(yaml);
      final copilot = catalog.providers['copilot']!;
      expect(copilot.auth.kind, AuthKind.oauth);
      expect(copilot.auth.envVar, isNull);
      expect(copilot.auth.helpUrl, 'https://github.com/login/device');
    });

    test('apiKey shorthand carries through help_url', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: anthropic/claude
capabilities: {}
providers:
  anthropic:
    name: Anthropic
    adapter: anthropic
    auth:
      api_key: env:ANTHROPIC_API_KEY
      help_url: https://console.anthropic.com/settings/keys
    models:
      claude:
        name: Claude
''';
      final catalog = parseCatalogYaml(yaml);
      final a = catalog.providers['anthropic']!;
      expect(a.auth.kind, AuthKind.apiKey);
      expect(a.auth.envVar, 'ANTHROPIC_API_KEY');
      expect(a.auth.helpUrl, contains('anthropic.com'));
    });

    test('parses request_headers map', () {
      const yaml = '''
version: 1
updated_at: 2026-04-19
defaults:
  model: openrouter/anthropic/claude-sonnet-4.6
capabilities: {}
providers:
  openrouter:
    name: OpenRouter
    adapter: openai
    compatibility: openrouter
    base_url: https://openrouter.ai/api/v1
    request_headers:
      HTTP-Referer: https://getglue.dev
      X-Title: Glue
    auth:
      api_key: env:OPENROUTER_API_KEY
    models:
      anthropic/claude-sonnet-4.6:
        name: Claude Sonnet 4.6 via OpenRouter
''';

      final catalog = parseCatalogYaml(yaml);
      final openrouter = catalog.providers['openrouter']!;
      expect(openrouter.requestHeaders, {
        'HTTP-Referer': 'https://getglue.dev',
        'X-Title': 'Glue',
      });
      expect(
        openrouter.models.keys,
        ['anthropic/claude-sonnet-4.6'],
        reason: 'model IDs may contain slashes',
      );
    });
  });
}
