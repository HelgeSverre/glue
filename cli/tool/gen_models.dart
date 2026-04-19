// ignore_for_file: avoid_print
/// Generates `lib/src/catalog/models_generated.dart` from the canonical
/// reference catalog at `../docs/reference/models.yaml`.
///
/// Usage:
///   dart run tool/gen_models.dart          # regenerate in place
///   dart run tool/gen_models.dart --check  # exit 1 if file would change
///
/// CI runs `--check` via `just gen-check` so a drifted commit fails fast.
library;

import 'dart:io';

import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/catalog/model_catalog.dart';

const _sourcePath = '../docs/reference/models.yaml';
const _outPath = 'lib/src/catalog/models_generated.dart';

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

String _render(ModelCatalog c) {
  final b = StringBuffer()
    ..writeln('// GENERATED — DO NOT EDIT.')
    ..writeln('// Source: docs/reference/models.yaml')
    ..writeln('// Regenerate with: dart run tool/gen_models.dart')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln("import 'package:glue/src/catalog/model_catalog.dart';")
    ..writeln()
    ..writeln('const ModelCatalog bundledCatalog = ModelCatalog(')
    ..writeln('  version: ${c.version},')
    ..writeln('  updatedAt: ${_str(c.updatedAt)},')
    ..writeln('  defaults: DefaultsConfig(')
    ..writeln('    model: ${_str(c.defaults.model)},')
    ..writeln('    smallModel: ${_strOrNull(c.defaults.smallModel)},')
    ..writeln('    localModel: ${_strOrNull(c.defaults.localModel)},')
    ..writeln('  ),')
    ..writeln('  capabilities: ${_renderStringMap(c.capabilities, indent: 2)},')
    ..writeln('  providers: {');

  for (final id in c.providers.keys) {
    final p = c.providers[id]!;
    b
      ..writeln('    ${_str(id)}: ProviderDef(')
      ..writeln('      id: ${_str(p.id)},')
      ..writeln('      name: ${_str(p.name)},')
      ..writeln('      adapter: ${_str(p.adapter)},')
      ..writeln('      compatibility: ${_strOrNull(p.compatibility)},')
      ..writeln('      enabled: ${p.enabled},')
      ..writeln('      baseUrl: ${_strOrNull(p.baseUrl)},')
      ..writeln('      docsUrl: ${_strOrNull(p.docsUrl)},')
      ..writeln('      auth: ${_renderAuth(p.auth)},')
      ..writeln(
        '      requestHeaders: ${_renderStringMap(p.requestHeaders, indent: 6)},',
      )
      ..writeln('      models: {');

    for (final mid in p.models.keys) {
      final m = p.models[mid]!;
      b
        ..writeln('        ${_str(mid)}: ModelDef(')
        ..writeln('          id: ${_str(m.id)},')
        ..writeln('          name: ${_str(m.name)},')
        ..writeln('          recommended: ${m.recommended},')
        ..writeln('          isDefault: ${m.isDefault},')
        ..writeln(
            '          capabilities: ${_renderStringSet(m.capabilities)},')
        ..writeln('          contextWindow: ${m.contextWindow},')
        ..writeln('          maxOutputTokens: ${m.maxOutputTokens},')
        ..writeln('          speed: ${_strOrNull(m.speed)},')
        ..writeln('          cost: ${_strOrNull(m.cost)},')
        ..writeln('          notes: ${_strOrNull(m.notes)},')
        ..writeln('        ),');
    }
    b
      ..writeln('      },')
      ..writeln('    ),');
  }

  b
    ..writeln('  },')
    ..writeln(');')
    ..writeln();
  return b.toString();
}

String _renderAuth(AuthSpec a) {
  final envVar = _strOrNull(a.envVar);
  return 'AuthSpec(kind: AuthKind.${a.kind.name}, envVar: $envVar)';
}

String _renderStringMap(Map<String, String> m, {required int indent}) {
  if (m.isEmpty) return '{}';
  final pad = ' ' * indent;
  final inner = ' ' * (indent + 2);
  final buf = StringBuffer('{\n');
  final keys = m.keys.toList()..sort();
  for (final k in keys) {
    buf.writeln('$inner${_str(k)}: ${_str(m[k]!)},');
  }
  buf.write('$pad}');
  return buf.toString();
}

String _renderStringSet(Set<String> s) {
  if (s.isEmpty) return '<String>{}';
  final keys = s.toList()..sort();
  return '{${keys.map(_str).join(', ')}}';
}

String _str(String s) {
  final escaped =
      s.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$').replaceAll("'", r"\'");
  return "'$escaped'";
}

String _strOrNull(String? s) => s == null ? 'null' : _str(s);
