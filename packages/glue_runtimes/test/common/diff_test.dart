import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

import 'package:glue_runtimes/src/common/diff.dart';

void main() {
  group('captureWorkspaceDiff', () {
    test('reports noBootstrapSha when bootstrapSha is null', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(),
        runtimeCwd: '/workspace',
        bootstrapSha: null,
        runtimeId: 'daytona',
      );
      expect(result, isA<DiffUnavailable>());
      expect((result as DiffUnavailable).reason,
          DiffUnavailableReason.noBootstrapSha);
    });

    test('reports noBootstrapSha when bootstrapSha is empty', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(),
        runtimeCwd: '/workspace',
        bootstrapSha: '',
        runtimeId: 'daytona',
      );
      expect(result, isA<DiffUnavailable>());
      expect((result as DiffUnavailable).reason,
          DiffUnavailableReason.noBootstrapSha);
    });

    test('reports gitFailed when git exits non-zero', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(exitCode: 128, stdout: 'fatal: bad sha'),
        runtimeCwd: '/workspace',
        bootstrapSha: 'deadbeef',
        runtimeId: 'daytona',
      );
      expect(result, isA<DiffUnavailable>());
      expect((result as DiffUnavailable).reason,
          DiffUnavailableReason.gitFailed);
      expect(result.hint, contains('fatal: bad sha'));
    });

    test('reports executorDead when the exec call throws', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(throwOnRun: true),
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
        runtimeId: 'modal',
      );
      expect(result, isA<DiffUnavailable>());
      expect((result as DiffUnavailable).reason,
          DiffUnavailableReason.executorDead);
    });

    test('returns DiffSuccess with the diff body on a non-empty patch',
        () async {
      const patch = 'diff --git a/foo b/foo\n--- a/foo\n+++ b/foo\n@@\n-x\n+y\n';
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(stdout: patch),
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
        runtimeId: 'daytona',
        sandboxId: 'sb-1',
      );
      expect(result, isA<DiffSuccess>());
      final success = result as DiffSuccess;
      expect(success.patch, patch);
      expect(success.meta.runtimeId, 'daytona');
      expect(success.meta.sandboxId, 'sb-1');
      expect(success.meta.bootstrapSha, 'abc123');
      expect(success.meta.sizeBytes, patch.length);
    });

    test('returns DiffEmpty when the patch body is empty', () async {
      final result = await captureWorkspaceDiff(
        executor: _FakeExecutor(stdout: ''),
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc',
        runtimeId: 'daytona',
      );
      expect(result, isA<DiffEmpty>());
    });

    test('issues the git diff command at runtimeCwd', () async {
      final exec = _FakeExecutor();
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
        runtimeId: 'daytona',
      );
      expect(exec.lastCommand, contains("git -C '/workspace' diff 'abc123'"));
    });

    test('quotes paths with single quotes safely', () async {
      final exec = _FakeExecutor();
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: "/work'space",
        bootstrapSha: 'abc',
        runtimeId: 'daytona',
      );
      expect(exec.lastCommand, contains(r"'/work'\''space'"));
    });
  });
}

class _FakeExecutor implements CommandExecutor {
  _FakeExecutor({
    this.exitCode = 0,
    this.stdout = '',
    this.throwOnRun = false,
  });
  final int exitCode;
  final String stdout;
  final bool throwOnRun;
  String? lastCommand;

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    lastCommand = command;
    if (throwOnRun) throw StateError('executor dead');
    return CaptureResult(exitCode: exitCode, stdout: stdout, stderr: '');
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      throw UnimplementedError();
}
