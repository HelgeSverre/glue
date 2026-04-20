/// End-to-end verification that `--model` (or `GLUE_MODEL`) is resolved
/// correctly through [GlueConfig.load] for the full user-input matrix that
/// Phase 1 of the model-resolver plan targets.
///
/// Covers the real catalog (`bundledCatalog`) rather than a fabricated one
/// so regressions tied to catalog content (e.g. a future release adding a
/// second `gemma4:*` entry) surface here.
library;

import 'dart:io';

import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:test/test.dart';

Directory _scratchHome() =>
    Directory.systemTemp.createTempSync('glue_model_flag_test_');

Environment _env(Directory home, {Map<String, String> vars = const {}}) =>
    Environment.test(home: home.path, vars: vars);

GlueConfig _load(String cliModel, {Directory? home}) {
  final h = home ?? _scratchHome();
  addTearDown(() {
    if (h.existsSync()) h.deleteSync(recursive: true);
  });
  return GlueConfig.load(cliModel: cliModel, environment: _env(h));
}

void main() {
  group('model flag — catalogued exact match', () {
    test('catalog key resolves and apiId reaches the adapter', () {
      final config = _load('anthropic/claude-sonnet-4-6');
      expect(config.activeModel, ModelRef.parse('anthropic/claude-sonnet-4-6'));
      final resolved = config.resolveModel(config.activeModel);
      expect(resolved.def.apiId, 'claude-sonnet-4-6');
    });

    test('bare display-name match resolves (single-provider id)', () {
      // `gemma4:26b` is only in Ollama, so bare form is unambiguous.
      final config = _load('gemma4:26b');
      expect(config.activeModel, ModelRef.parse('ollama/gemma4:26b'));
    });
  });

  group('model flag — passthrough for explicit provider/id', () {
    test('ollama/gemma4:latest (uncatalogued) passes through verbatim', () {
      final config = _load('ollama/gemma4:latest');
      expect(config.activeModel.providerId, 'ollama');
      expect(config.activeModel.modelId, 'gemma4:latest');
      // resolveModel synthesises a ModelDef so adapters see the raw id.
      final resolved = config.resolveModel(config.activeModel);
      expect(resolved.def.id, 'gemma4:latest');
      expect(resolved.def.apiId, 'gemma4:latest');
    });
  });

  group('model flag — silent coercion is gone', () {
    test('bare "gemma4" no longer fuzz-matches to gemma4:26b', () {
      expect(
        () => _load('gemma4'),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'message',
            contains('could not resolve model "gemma4"'),
          ),
        ),
      );
    });

    test('ambiguous bare input lists candidates instead of picking one', () {
      // claude-sonnet-4-6 is in anthropic, copilot, and openrouter.
      expect(
        () => _load('claude-sonnet-4-6'),
        throwsA(
          isA<ConfigError>()
              .having(
                  (e) => e.message, 'lists anthropic', contains('anthropic/'))
              .having(
                (e) => e.message,
                'calls out ambiguity',
                contains('ambiguous'),
              ),
        ),
      );
    });

    test('unknown provider in explicit ref errors, not passes through', () {
      expect(
        () => _load('madeup/whatever'),
        throwsA(
          isA<ConfigError>().having(
            (e) => e.message,
            'names the provider',
            contains('unknown provider "madeup"'),
          ),
        ),
      );
    });
  });

  group('model flag — env var and precedence still work', () {
    test('GLUE_MODEL env var with explicit passthrough resolves cleanly', () {
      final home = _scratchHome();
      addTearDown(() => home.deleteSync(recursive: true));
      final config = GlueConfig.load(
        environment: _env(
          home,
          vars: {'GLUE_MODEL': 'ollama/qwen3:30b'},
        ),
      );
      expect(config.activeModel.providerId, 'ollama');
      expect(config.activeModel.modelId, 'qwen3:30b');
    });
  });
}
