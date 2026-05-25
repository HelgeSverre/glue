// ignore_for_file: avoid_print
/// Generates `../packages/glue_harness/lib/src/catalog/models_generated.dart`
/// from the canonical reference catalog at `../docs/reference/models.yaml`.
///
/// Usage (run from `cli/`):
///   dart run tool/gen_models.dart          # regenerate in place
///   dart run tool/gen_models.dart --check  # exit 1 if file would change
///
/// CI runs `--check` via `just gen-check` so a drifted commit fails fast.
library;

import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';

const _sourcePath = '../docs/reference/models.yaml';
const _outPath =
    '../packages/glue_harness/lib/src/catalog/models_generated.dart';

void main(List<String> args) {
  final checkMode = args.contains('--check');

  final yaml = File(_sourcePath).readAsStringSync();
  final catalog = parseCatalogYaml(yaml);
  final rendered = _dartFormat(_render(catalog));

  final outFile = File(_outPath);
  final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';

  if (checkMode) {
    if (existing != rendered) {
      stderr.writeln(
        '$_outPath is stale. Run `dart run tool/gen_models.dart` to regenerate.',
      );
      exit(1);
    }
    print('ok: $_outPath is up to date.');
    return;
  }

  if (existing == rendered) {
    print('no change: $_outPath');
    return;
  }
  outFile.writeAsStringSync(rendered);
  print('wrote $_outPath (${catalog.providers.length} providers)');
}

String _dartFormat(String source) {
  final tmp = File(
    '${Directory.systemTemp.path}/glue_gen_models_${pid}_${DateTime.now().microsecondsSinceEpoch}.dart',
  )..writeAsStringSync(source);
  try {
    final result = Process.runSync('dart', ['format', tmp.path]);
    if (result.exitCode != 0) {
      throw StateError('dart format failed: ${result.stderr}');
    }
    return tmp.readAsStringSync();
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

String _render(ModelCatalog catalog) {
  final json = const JsonEncoder.withIndent('  ').convert(catalog.toMap());
  assert(!json.contains("'''"), 'JSON contains triple-quote sequence');
  return """
// GENERATED — DO NOT EDIT.
// Source: docs/reference/models.yaml
// Regenerate with: dart run tool/gen_models.dart
// ignore_for_file: lines_longer_than_80_chars

import 'package:glue_core/glue_core.dart';

const String _bundledCatalogJson = r'''
$json
''';

final ModelCatalog bundledCatalog =
    ModelCatalogMapper.fromJson(_bundledCatalogJson);
""";
}
