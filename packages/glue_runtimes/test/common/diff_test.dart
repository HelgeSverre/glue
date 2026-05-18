import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/diff.dart';

void main() {
  group('captureWorkspaceDiff', () {
    test('returns null when bootstrapSha is null', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(),
        runtimeCwd: '/workspace',
        bootstrapSha: null,
      );
      expect(result, isNull);
    });

    test('returns null when bootstrapSha is empty', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(),
        runtimeCwd: '/workspace',
        bootstrapSha: '',
      );
      expect(result, isNull);
    });

    test('returns null when git exits non-zero', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(exitCode: 128, stdout: 'fatal: bad sha'),
        runtimeCwd: '/workspace',
        bootstrapSha: 'deadbeef',
      );
      expect(result, isNull);
    });

    test('returns the diff body on success', () async {
      const patch = 'diff --git a/foo b/foo\n--- a/foo\n+++ b/foo\n@@\n-x\n+y\n';
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(stdout: patch),
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
      );
      expect(result, patch);
    });

    test('issues the git diff command at runtimeCwd', () async {
      final exec = _FakeExecutor();
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
      );
      expect(exec.lastCommand, contains("git -C '/workspace' diff 'abc123'"));
    });

    test('quotes paths with single quotes safely', () async {
      final exec = _FakeExecutor();
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: "/work'space",
        bootstrapSha: 'abc',
      );
      expect(exec.lastCommand, contains(r"'/work'\''space'"));
    });
  });
}

class _FakeExecutor implements CommandExecutor {
  _FakeExecutor({this.exitCode = 0, this.stdout = ''});
  final int exitCode;
  final String stdout;
  String? lastCommand;

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    lastCommand = command;
    return CaptureResult(exitCode: exitCode, stdout: stdout, stderr: '');
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      throw UnimplementedError();
}
