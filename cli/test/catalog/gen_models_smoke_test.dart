/// Smoke test for the bundled catalog generator.
///
/// Validates two things:
///   1. The committed `lib/src/catalog/models_generated.dart` exposes a
///      non-empty `bundledCatalog` whose shape matches the source YAML.
///   2. Running `tool/gen_models.dart --check` against the source YAML does
///      not produce a diff (the committed file is up to date).
library;

import 'dart:io';

import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/catalog/models_generated.dart';
import 'package:test/test.dart';

void main() {
  group('bundled generated catalog', () {
    test('matches the source YAML catalog', () {
      final yaml = File('../docs/reference/models.yaml').readAsStringSync();
      final fromYaml = parseCatalogYaml(yaml);

      expect(bundledCatalog.version, fromYaml.version);
      expect(bundledCatalog.defaults.model, fromYaml.defaults.model);
      expect(bundledCatalog.defaults.smallModel, fromYaml.defaults.smallModel);
      expect(bundledCatalog.providers.keys, fromYaml.providers.keys);

      for (final providerId in fromYaml.providers.keys) {
        final generated = bundledCatalog.providers[providerId]!;
        final expected = fromYaml.providers[providerId]!;
        expect(generated.adapter, expected.adapter, reason: providerId);
        expect(generated.compatibility, expected.compatibility,
            reason: providerId);
        expect(generated.baseUrl, expected.baseUrl, reason: providerId);
        expect(generated.auth.kind, expected.auth.kind, reason: providerId);
        expect(generated.auth.envVar, expected.auth.envVar, reason: providerId);
        expect(generated.models.keys, expected.models.keys, reason: providerId);
      }
    });

    test('generator --check succeeds (committed file is up to date)', () async {
      final result = await Process.run(
        'dart',
        ['run', 'tool/gen_models.dart', '--check'],
      );
      expect(
        result.exitCode,
        0,
        reason:
            'Generated file is stale. Run `dart run tool/gen_models.dart` to regenerate.\n'
            'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
    }, tags: ['codegen']);
  });
}
