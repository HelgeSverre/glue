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

    test('reports gitFailed when format-patch exits non-zero', () async {
      // The add -N preamble swallows errors with `|| true`, so we
      // script three steps: add → succeed, format-patch → fail,
      // diff → never reached.
      final exec = _ScriptedExecutor([
        _Step(stdout: ''),
        _Step(exitCode: 128, stderr: 'fatal: bad sha'),
      ]);
      final result = await captureWorkspaceDiff(
        executor: exec,
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

    test('returns DiffSuccess concatenating format-patch + worktree diff',
        () async {
      const mbox = 'From abc Mon Sep 17 ...\nSubject: agent commit\n';
      const wt = 'diff --git a/foo b/foo\n@@\n-x\n+y\n';
      final exec = _ScriptedExecutor([
        _Step(stdout: ''), // add -N
        _Step(stdout: mbox), // format-patch
        _Step(stdout: wt), // diff
      ]);
      final result = await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
        runtimeId: 'daytona',
        sandboxId: 'sb-1',
      );
      expect(result, isA<DiffSuccess>());
      final success = result as DiffSuccess;
      expect(success.patch, '$mbox$wt');
      expect(success.meta.runtimeId, 'daytona');
      expect(success.meta.sandboxId, 'sb-1');
      expect(success.meta.bootstrapSha, 'abc123');
      expect(success.meta.format, 'format-patch');
      expect(success.meta.sizeBytes, success.patch.length);
    });

    test('returns DiffEmpty when both steps produce nothing', () async {
      final exec = _ScriptedExecutor([
        _Step(stdout: ''),
        _Step(stdout: ''),
        _Step(stdout: ''),
      ]);
      final result = await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc',
        runtimeId: 'daytona',
      );
      expect(result, isA<DiffEmpty>());
    });

    test('intent-to-add runs before format-patch so untracked files appear',
        () async {
      final exec = _ScriptedExecutor([
        _Step(stdout: ''),
        _Step(stdout: ''),
        _Step(stdout: ''),
      ]);
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc',
        runtimeId: 'daytona',
      );
      expect(exec.commands[0], contains('add -N'));
      expect(exec.commands[1], contains('format-patch'));
      expect(exec.commands[2], contains('diff --binary'));
    });

    test('format-patch range is bootstrapSha..HEAD with binary + rename detection',
        () async {
      final exec = _ScriptedExecutor([
        _Step(stdout: ''),
        _Step(stdout: ''),
        _Step(stdout: ''),
      ]);
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: '/workspace',
        bootstrapSha: 'abc123',
        runtimeId: 'daytona',
      );
      expect(exec.commands[1], contains("format-patch --binary -M -C --stdout 'abc123'..HEAD"));
      expect(exec.commands[2], contains('diff --binary -M -C HEAD'));
    });

    test('quotes paths with single quotes safely', () async {
      final exec = _ScriptedExecutor([
        _Step(stdout: ''),
        _Step(stdout: ''),
        _Step(stdout: ''),
      ]);
      await captureWorkspaceDiff(
        executor: exec,
        runtimeCwd: "/work'space",
        bootstrapSha: 'abc',
        runtimeId: 'daytona',
      );
      expect(exec.commands[0], contains(r"-C '/work'\''space'"));
    });
  });
}

class _FakeExecutor implements CommandExecutor {
  _FakeExecutor({this.throwOnRun = false});
  final bool throwOnRun;
  String? lastCommand;

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    lastCommand = command;
    if (throwOnRun) throw StateError('executor dead');
    return CaptureResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      throw UnimplementedError();
}

class _Step {
  _Step({
    // ignore: unused_element_parameter
    this.exitCode = 0,
    // ignore: unused_element_parameter
    this.stdout = '',
    this.stderr = '',
  });
  final int exitCode;
  final String stdout;
  final String stderr;
}

class _ScriptedExecutor implements CommandExecutor {
  _ScriptedExecutor(this._steps);
  final List<_Step> _steps;
  final List<String> commands = [];
  int _i = 0;

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    commands.add(command);
    final step = _steps[_i++];
    return CaptureResult(
      exitCode: step.exitCode,
      stdout: step.stdout,
      stderr: step.stderr,
    );
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      throw UnimplementedError();
}
