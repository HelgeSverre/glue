import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/catalog/model_resolver.dart';
import 'package:glue/src/catalog/models_generated.dart';
import 'package:test/test.dart';

void main() {
  group('resolveModelInput — explicit provider/id', () {
    test('catalogued ref resolves to ResolvedExact', () {
      final out = resolveModelInput(
        'anthropic/claude-sonnet-4-6',
        bundledCatalog,
      );
      expect(out, isA<ResolvedExact>());
      final exact = out as ResolvedExact;
      expect(exact.ref.providerId, 'anthropic');
      expect(exact.ref.modelId, 'claude-sonnet-4-6');
      expect(exact.def.apiId, 'claude-sonnet-4-6');
    });

    test('uncatalogued tag on known provider passes through verbatim', () {
      final out = resolveModelInput(
        'ollama/gemma4:latest',
        bundledCatalog,
      );
      expect(out, isA<ResolvedPassthrough>());
      final pass = out as ResolvedPassthrough;
      expect(pass.providerKnown, isTrue);
      expect(pass.ref.providerId, 'ollama');
      expect(pass.ref.modelId, 'gemma4:latest');
    });

    test('unknown provider is flagged so callers can error', () {
      final out = resolveModelInput('madeup/whatever', bundledCatalog);
      expect(out, isA<ResolvedPassthrough>());
      final pass = out as ResolvedPassthrough;
      expect(pass.providerKnown, isFalse);
      expect(pass.ref.providerId, 'madeup');
    });

    test('slashes inside model id are preserved', () {
      final out = resolveModelInput(
        'openrouter/anthropic/claude-sonnet-4-6',
        bundledCatalog,
      );
      expect(out, isA<ResolvedPassthrough>());
      expect((out as ResolvedPassthrough).ref.modelId,
          'anthropic/claude-sonnet-4-6');
    });
  });

  group('resolveModelInput — bare input', () {
    test('exact id match is unambiguous when only one provider has it', () {
      final out = resolveModelInput('gemma4:26b', bundledCatalog);
      expect(out, isA<ResolvedExact>());
      final exact = out as ResolvedExact;
      expect(exact.ref.providerId, 'ollama');
      expect(exact.ref.modelId, 'gemma4:26b');
    });

    test('exact display-name match resolves (case-insensitive)', () {
      final out = resolveModelInput('Claude Opus 4.6', bundledCatalog);
      expect(out, isA<ResolvedExact>());
      expect((out as ResolvedExact).ref.providerId, 'anthropic');
    });

    test('substring-only input no longer coerces — gemma4 is unknown', () {
      final out = resolveModelInput('gemma4', bundledCatalog);
      expect(out, isA<UnknownBareInput>());
    });

    test('id shared by multiple providers is flagged ambiguous', () {
      // claude-sonnet-4-6 appears in anthropic, copilot, and openrouter.
      final out = resolveModelInput('claude-sonnet-4-6', bundledCatalog);
      expect(out, isA<AmbiguousBareInput>());
      final ambig = out as AmbiguousBareInput;
      expect(ambig.candidates.length, greaterThanOrEqualTo(2));
      final providers = ambig.candidates.map((c) => c.ref.providerId).toSet();
      expect(providers, containsAll(<String>{'anthropic'}));
      // At least one of the other providers is present too.
      expect(providers.length, greaterThanOrEqualTo(2));
    });

    test('unknown bare input returns UnknownBareInput, never passthrough', () {
      final out = resolveModelInput('totally-made-up-model', bundledCatalog);
      expect(out, isA<UnknownBareInput>());
      expect((out as UnknownBareInput).raw, 'totally-made-up-model');
    });
  });

  group('resolveModelInput — fabricated catalog edge cases', () {
    test('handles the two-provider ambiguity case cleanly', () {
      const catalog = ModelCatalog(
        version: 1,
        updatedAt: '2026-04-20',
        defaults: DefaultsConfig(model: 'alpha/foo'),
        capabilities: {},
        providers: {
          'alpha': ProviderDef(
            id: 'alpha',
            name: 'Alpha',
            adapter: 'openai',
            auth: AuthSpec(kind: AuthKind.none),
            models: {
              'foo': ModelDef(id: 'foo', name: 'Foo'),
            },
          ),
          'beta': ProviderDef(
            id: 'beta',
            name: 'Beta',
            adapter: 'openai',
            auth: AuthSpec(kind: AuthKind.none),
            models: {
              'foo': ModelDef(id: 'foo', name: 'Foo'),
            },
          ),
        },
      );

      final out = resolveModelInput('foo', catalog);
      expect(out, isA<AmbiguousBareInput>());
      final refs = (out as AmbiguousBareInput)
          .candidates
          .map((c) => c.ref.toString())
          .toSet();
      expect(refs, {'alpha/foo', 'beta/foo'});
    });

    test('empty raw input is UnknownBareInput, not a crash', () {
      final out = resolveModelInput('', bundledCatalog);
      expect(out, isA<UnknownBareInput>());
    });
  });

  group('resolveModelInput integrates with ModelRef round-trip', () {
    test('resolved ref toString is usable as input next session', () {
      final out = resolveModelInput(
        'anthropic/claude-sonnet-4-6',
        bundledCatalog,
      );
      final ref = (out as ResolvedExact).ref;
      expect(ref.toString(), 'anthropic/claude-sonnet-4-6');
      expect(ModelRef.parse(ref.toString()), ref);
    });
  });
}
