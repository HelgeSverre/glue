import 'package:glue/src/app/model_display.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/catalog/models_generated.dart';
import 'package:test/test.dart';

void main() {
  group('formatStatusModelLabel', () {
    test('catalogued ref with apiId == id shows provider · id', () {
      final label = formatStatusModelLabel(
        ModelRef.parse('anthropic/claude-sonnet-4-6'),
        bundledCatalog,
        'fallback',
      );
      expect(label, 'anthropic · claude-sonnet-4-6');
    });

    test('uncatalogued Ollama tag falls back to modelId verbatim', () {
      final label = formatStatusModelLabel(
        ModelRef.parse('ollama/gemma4:latest'),
        bundledCatalog,
        'fallback',
      );
      expect(label, 'ollama · gemma4:latest');
    });

    test('null ref uses the fallback (pre-config bootstrap)', () {
      expect(
        formatStatusModelLabel(null, bundledCatalog, 'booting'),
        'booting',
      );
    });

    test('null catalog gracefully falls back to raw modelId', () {
      final label = formatStatusModelLabel(
        ModelRef.parse('ollama/whatever'),
        null,
        'fallback',
      );
      expect(label, 'ollama · whatever');
    });

    test('apiId override surfaces on status bar', () {
      // Exercise a synthetic catalog where apiId != id.
      const catalog = ModelCatalog(
        version: 1,
        updatedAt: '2026-04-20',
        defaults: DefaultsConfig(model: 'groq/foo'),
        capabilities: {},
        providers: {
          'groq': ProviderDef(
            id: 'groq',
            name: 'Groq',
            adapter: 'openai',
            auth: AuthSpec(kind: AuthKind.apiKey),
            models: {
              'foo': ModelDef(id: 'foo', name: 'Foo', apiId: 'vendor/foo'),
            },
          ),
        },
      );
      final label = formatStatusModelLabel(
        ModelRef.parse('groq/foo'),
        catalog,
        'fallback',
      );
      expect(label, 'groq · vendor/foo');
    });
  });

  group('formatInfoModelLabel', () {
    test('catalogued ref shows display name and wire address', () {
      final label = formatInfoModelLabel(
        ModelRef.parse('anthropic/claude-sonnet-4-6'),
        bundledCatalog,
        'fallback',
      );
      expect(label, 'Claude Sonnet 4.6 — anthropic/claude-sonnet-4-6');
    });

    test('uncatalogued passthrough shows the raw ref only', () {
      final label = formatInfoModelLabel(
        ModelRef.parse('ollama/gemma4:latest'),
        bundledCatalog,
        'fallback',
      );
      expect(label, 'ollama/gemma4:latest');
    });

    test('null ref uses the fallback', () {
      expect(
        formatInfoModelLabel(null, bundledCatalog, 'fallback'),
        'fallback',
      );
    });
  });
}
