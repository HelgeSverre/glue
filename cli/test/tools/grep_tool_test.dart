import 'dart:async';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

/// Records every command sent to [runCapture] and returns a scripted
/// result, so we can assert the GrepTool builds the right shell command
/// without depending on `rg`/`grep` being installed on the test host.
class _RecordingExecutor implements CommandExecutor {
  final CaptureResult Function(String command) onRun;
  final List<String> commands = [];

  _RecordingExecutor(this.onRun);

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    commands.add(command);
    return onRun(command);
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      throw UnimplementedError();
}

void main() {
  group('GrepTool', () {
    test('builds an rg-or-grep shell pipeline and quotes args', () async {
      final exec = _RecordingExecutor(
        (_) => CaptureResult(
          exitCode: 0,
          stdout: 'lib/foo.dart:3:final foo = 1;\n',
          stderr: '',
        ),
      );
      final tool = GrepTool(exec);
      final result = await tool.execute({'pattern': 'foo', 'path': 'lib'});
      expect(exec.commands, hasLength(1));
      final cmd = exec.commands.single;
      expect(cmd, contains('command -v rg'));
      expect(cmd, contains("'foo'"));
      expect(cmd, contains("'lib'"));
      expect(result.content, contains('foo.dart'));
      expect(result.metadata['match_count'], 1);
    });

    test('reports no matches when stdout is empty', () async {
      final exec = _RecordingExecutor(
        (_) => CaptureResult(exitCode: 1, stdout: '', stderr: ''),
      );
      final tool = GrepTool(exec);
      final result = await tool.execute({'pattern': 'nope'});
      expect(result.content, contains('No matches found'));
      expect(result.metadata['match_count'], 0);
    });

    test('surfaces a timeout signal from the executor', () async {
      final exec = _RecordingExecutor(
        (_) => CaptureResult(exitCode: -1, stdout: '', stderr: ''),
      );
      final tool = GrepTool(exec);
      final result = await tool.execute({'pattern': 'whatever'});
      expect(result.success, isFalse);
      expect(result.metadata['timed_out'], isTrue);
    });

    test('safely escapes embedded single quotes in pattern', () async {
      final exec = _RecordingExecutor(
        (_) => CaptureResult(exitCode: 0, stdout: 'hit\n', stderr: ''),
      );
      final tool = GrepTool(exec);
      await tool.execute({'pattern': "it's", 'path': '.'});
      final cmd = exec.commands.single;
      // The shell-quote helper turns `it's` into `'it'\''s'`.
      expect(cmd, contains(r"'it'\''s'"));
    });

    test(
      'leaves a leading ~/ unquoted so the runtime shell expands it',
      () async {
        final exec = _RecordingExecutor(
          (_) => CaptureResult(exitCode: 0, stdout: '', stderr: ''),
        );
        final tool = GrepTool(exec);
        await tool.execute({'pattern': 'foo', 'path': '~/code/3d'});
        final cmd = exec.commands.single;
        // Tilde-prefix stays unquoted (so ~ expands); the rest is single-quoted.
        expect(cmd, contains(r"~/'code/3d'"));
        expect(cmd, isNot(contains("'~/code/3d'")));
      },
    );

    test('works end-to-end against a real HostExecutor', () async {
      // Smoke test using whichever of rg or grep is present on the test
      // host. We grep this file itself for a unique sentinel string.
      const sentinel = '__GREP_TEST_SENTINEL_jUkPV2__';
      final tool = GrepTool(HostExecutor(const ShellConfig(executable: 'sh')));
      final tmpDir = Directory.systemTemp.createTempSync('glue-grep-');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      File('${tmpDir.path}/target.txt').writeAsStringSync(
        'line one\nthis line has $sentinel in it\nline three\n',
      );
      final result = await tool.execute({
        'pattern': sentinel,
        'path': tmpDir.path,
      });
      expect(result.content, contains(sentinel));
      expect(result.metadata['match_count'], 1);
    });
  });
}
