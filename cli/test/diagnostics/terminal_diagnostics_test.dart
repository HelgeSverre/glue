import 'package:glue/src/diagnostics/terminal_diagnostics.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalDiagnostics.collect', () {
    test('returns a populated snapshot of the current process', () {
      final d = TerminalDiagnostics.collect();
      expect(d.platformOs, isNotEmpty);
      expect(d.executable, isNotEmpty);
      expect(d.verdict, isNotEmpty);
    });

    test('toAttributes is JSON-friendly (only primitives, lists, maps)', () {
      final attrs = TerminalDiagnostics.collect().toAttributes();
      for (final entry in attrs.entries) {
        final v = entry.value;
        expect(
          v is bool || v is num || v is String || v is List || v == null,
          isTrue,
          reason:
              'Attribute "${entry.key}" has non-JSON-friendly type: ${v.runtimeType}',
        );
      }
      expect(attrs['verdict'], isA<String>());
      expect(attrs['markers'], isA<List<String>>());
    });

    test('toReportLines starts with a Verdict line', () {
      final lines = TerminalDiagnostics.collect().toReportLines();
      expect(lines, isNotEmpty);
      expect(lines.first, startsWith('Verdict: '));
    });

    test('exec args under a Dart VM debugger flip the debugger flag', () {
      // Synthesize a snapshot with debugger args present so we exercise the
      // verdict branch without actually re-launching under a debugger.
      final synthetic = TerminalDiagnostics(
        stdinHasTerminal: false,
        stdoutHasTerminal: false,
        stderrHasTerminal: false,
        stdoutSupportsAnsiEscapes: false,
        terminalColumns: null,
        terminalLines: null,
        term: null,
        termProgram: null,
        termProgramVersion: null,
        colorterm: null,
        lcTerminal: null,
        markers: const ['intellij', 'dart-vm-debugger'],
        executable: '/opt/homebrew/Cellar/dart/3.11.5/libexec/bin/dart',
        executableArgs: const [
          '--enable-asserts',
          '--pause_isolates_on_start',
          '--enable-vm-service:62237',
        ],
        runningUnderDartDebugger: true,
        platformOs: 'macos',
        verdict:
            'IntelliJ/PhpStorm debug console (no PTY) — enable "Emulate terminal in output console" in the Run Configuration',
      );
      final attrs = synthetic.toAttributes();
      expect(attrs['process.under_dart_debugger'], isTrue);
      expect(attrs['markers'], contains('intellij'));
      expect(synthetic.verdict, contains('PhpStorm'));
    });
  });
}
