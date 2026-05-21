// ignore_for_file: avoid_print
/// Generates `../packages/glue_harness/lib/src/share/html/share_assets_generated.dart`
/// from the canonical share HTML template and stylesheet.
///
/// Usage (run from `cli/`):
///   dart run tool/gen_share_assets.dart          # regenerate in place
///   dart run tool/gen_share_assets.dart --check  # exit 1 if file would change
///
/// CI runs `--check` via `just gen-check` so a drifted commit fails fast.
///
/// Why: the AOT-compiled `glue` binary cannot read source-tree files at
/// runtime, so the share renderer needs the assets embedded as Dart string
/// constants.
library;

import 'dart:io';

const _templatePath =
    '../packages/glue_harness/lib/src/share/html/share_page_template.html';
const _cssPath = '../packages/glue_harness/lib/src/share/html/share_page.css';
const _outPath =
    '../packages/glue_harness/lib/src/share/html/share_assets_generated.dart';

void main(List<String> args) {
  final checkMode = args.contains('--check');

  final template = File(_templatePath).readAsStringSync();
  final css = File(_cssPath).readAsStringSync();

  _assertNoTripleQuote(_templatePath, template);
  _assertNoTripleQuote(_cssPath, css);

  final rendered = _dartFormat(_render(template: template, css: css));

  final outFile = File(_outPath);
  final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';

  if (checkMode) {
    if (existing != rendered) {
      stderr.writeln(
        '$_outPath is stale. Run `dart run tool/gen_share_assets.dart` to regenerate.',
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
  print('wrote $_outPath');
}

void _assertNoTripleQuote(String path, String content) {
  if (content.contains("'''")) {
    stderr.writeln(
      "$path contains ''' which would break raw-triple-quoted Dart string literals. "
      'Either remove the sequence from the source asset or extend the generator '
      'to use a different escaping strategy.',
    );
    exit(1);
  }
}

String _dartFormat(String source) {
  final tmp = File(
    '${Directory.systemTemp.path}/glue_gen_share_assets_${pid}_${DateTime.now().microsecondsSinceEpoch}.dart',
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

String _render({required String template, required String css}) {
  final b = StringBuffer()
    ..writeln('// GENERATED — DO NOT EDIT.')
    ..writeln(
      '// Source: packages/glue_harness/lib/src/share/html/share_page_template.html',
    )
    ..writeln(
      '//         packages/glue_harness/lib/src/share/html/share_page.css',
    )
    ..writeln('// Regenerate with: dart run tool/gen_share_assets.dart')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('const String sharePageTemplate = r\'\'\'')
    ..write(template)
    ..writeln("''';")
    ..writeln()
    ..writeln('const String sharePageStylesheet = r\'\'\'')
    ..write(css)
    ..writeln("''';");
  return b.toString();
}
