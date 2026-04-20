// ignore_for_file: avoid_print
/// Generates `lib/src/config/version_generated.dart` from the `version:`
/// field in `pubspec.yaml`, so `pubspec.yaml` is the single source of truth.
///
/// Usage:
///   dart run tool/gen_version.dart          # regenerate in place
///   dart run tool/gen_version.dart --check  # exit 1 if file would change
///
/// CI runs `--check` via `just gen-check` so a drifted commit fails fast.
library;

import 'dart:io';

const _sourcePath = 'pubspec.yaml';
const _outPath = 'lib/src/config/version_generated.dart';

void main(List<String> args) {
  final checkMode = args.contains('--check');

  final version = _extractVersion(File(_sourcePath).readAsStringSync());
  final rendered = _render(version);

  final outFile = File(_outPath);
  final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';

  if (checkMode) {
    if (existing != rendered) {
      stderr.writeln(
        '$_outPath is stale. Run `dart run tool/gen_version.dart` to regenerate.',
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
  print('wrote $_outPath (version $version)');
}

String _extractVersion(String pubspec) {
  // Simple line-scan avoids pulling the yaml package into tool/ deps.
  // Matches `version: 0.1.1` or `version: "0.1.1"`, at top-level (column 0).
  final re = RegExp(r'''^version:\s*["']?([^"'\s#]+)["']?''', multiLine: true);
  final match = re.firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('ERROR: no `version:` field found in $_sourcePath');
    exit(1);
  }
  return match.group(1)!;
}

String _render(String version) {
  return '// GENERATED — DO NOT EDIT.\n'
      '// Source: pubspec.yaml\n'
      '// Regenerate with: dart run tool/gen_version.dart\n'
      '\n'
      "const String packageVersion = '$version';\n";
}
