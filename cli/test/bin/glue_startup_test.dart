/// End-to-end tests for the top-level `glue` entrypoint in `bin/glue.dart`.
///
/// Uses the compiled Dart snapshot via `Process.run` so we exercise the real
/// exception-handling path in `main()`. Verifies that ConfigError surfaces
/// as a clean one-line "Error: …" + EX_CONFIG exit (78) rather than a Dart
/// "Unhandled exception" stack trace.
library;

import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _runGlue(List<String> args, {String stdin = ''}) async {
  final process = await Process.start(
    'dart',
    ['run', 'bin/glue.dart', ...args],
    workingDirectory: Directory.current.path,
    runInShell: true,
  );
  process.stdin.write(stdin);
  await process.stdin.close();
  final stdoutBytes =
      await process.stdout.transform(const SystemEncoding().decoder).join();
  final stderrBytes =
      await process.stderr.transform(const SystemEncoding().decoder).join();
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, stdoutBytes, stderrBytes);
}

void main() {
  // These tests spawn the dart VM; cap each generously. Runs serially to
  // avoid hammering the disk when the cache is cold.
  group('bin/glue.dart error handling', () {
    test(
      'unknown bare model exits 78 with clean message (no stack trace)',
      () async {
        final r = await _runGlue(['-p', '--model', 'totally-fake-model']);
        expect(r.exitCode, 78);
        expect(r.stderr.toString(), startsWith('Error: '));
        expect(r.stderr.toString(), contains('could not resolve'));
        expect(r.stderr.toString(), isNot(contains('Unhandled exception')));
        expect(r.stderr.toString(), isNot(contains('#0')));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'ambiguous bare model exits 78 with candidate list',
      () async {
        final r = await _runGlue(['-p', '--model', 'claude-sonnet-4-6']);
        expect(r.exitCode, 78);
        expect(r.stderr.toString(), contains('ambiguous'));
        expect(r.stderr.toString(), contains('anthropic/'));
        expect(r.stderr.toString(), isNot(contains('Unhandled exception')));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'unknown provider in explicit ref exits 78 cleanly',
      () async {
        final r = await _runGlue(['-p', '--model', 'madeup/foo']);
        expect(r.exitCode, 78);
        expect(r.stderr.toString(), contains('unknown provider'));
        expect(r.stderr.toString(), isNot(contains('Unhandled exception')));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
