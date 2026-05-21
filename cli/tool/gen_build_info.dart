// ignore_for_file: avoid_print
/// Generates `packages/glue_harness/lib/src/config/build_info_generated.dart`
/// with build metadata (timestamp, git SHA, etc.).
///
/// Unlike version_generated.dart, this file is intended to change on every
/// build and should generally be .ignored (or handled as a build artifact).
library;

import 'dart:io';

const _outPath =
    '../packages/glue_harness/lib/src/config/build_info_generated.dart';

void main(List<String> args) {
  final now = DateTime.now().toUtc().toIso8601String();

  final gitSha = _run('git', ['rev-parse', '--short', 'HEAD']) ?? 'unknown';

  final isDirty = _run('git', ['diff', '--quiet']) == null ? '+dirty' : '';
  final builtBy = Platform.environment['USER'] ?? 'unknown';
  final hostname = Platform.localHostname;

  final rendered =
      '''
// GENERATED — DO NOT EDIT.
// Regenerate with: dart run tool/gen_build_info.dart

const String packageBuildTime = '$now';
const String packageGitSha = '$gitSha';
const String packageGitDirty = '$isDirty';
const String packageBuiltBy = '$builtBy@$hostname';
''';

  final outFile = File(_outPath);
  final existing = outFile.existsSync() ? outFile.readAsStringSync() : '';

  if (existing == rendered) {
    return;
  }

  outFile.writeAsStringSync(rendered);
  print('wrote $_outPath');
}

String? _run(String cmd, List<String> args) {
  try {
    final result = Process.runSync(cmd, args);
    if (result.exitCode == 0) {
      return result.stdout.toString().trim();
    }
  } catch (_) {}
  return null;
}
