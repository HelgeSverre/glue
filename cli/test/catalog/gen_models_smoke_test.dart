/// Smoke test for the bundled catalog generator.
///
/// Validates two things:
///   1. The committed `lib/src/catalog/models_generated.dart` exposes a
///      non-empty `bundledCatalog` whose shape matches the source YAML.
///   2. Running `tool/gen_models.dart --check` against the source YAML does
///      not produce a diff (the committed file is up to date).
library;

import 'dart:io';

import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  group('bundled generated catalog', () {
    test('matches the source YAML catalog', () {
      final yaml = File('../docs/reference/models.yaml').readAsStringSync();
      final fromYaml = parseCatalogYaml(yaml);

      expect(bundledCatalog, equals(fromYaml));
    });

    test(
      'generator --check succeeds (committed file is up to date)',
      () async {
        final result = await Process.run('dart', [
          'run',
          'tool/gen_models.dart',
          '--check',
        ]);
        expect(
          result.exitCode,
          0,
          reason:
              'Generated file is stale. Run `dart run tool/gen_models.dart` to regenerate.\n'
              'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
        );
      },
      tags: ['codegen'],
    );
  });
}
