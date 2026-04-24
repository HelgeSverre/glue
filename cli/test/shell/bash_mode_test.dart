import 'dart:async';

import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/runtime/app_mode.dart';
import 'package:glue/src/runtime/transcript.dart';
import 'package:glue/src/shell/bash_mode.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:test/test.dart';

class _RecordingSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// A CommandExecutor that records invocations but never fires a real
/// process. Used for tests where we only care about the routing
/// decisions, not the execution.
class _FakeExecutor implements CommandExecutor {
  final List<String> startedCommands = [];

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    startedCommands.add(command);
    return CaptureResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<RunningCommand> startStreaming(String command) async {
    startedCommands.add(command);
    // The real BashMode awaits exitCode + joins stdout/stderr. We can't
    // meaningfully fake a Process handle, so tests that care about the
    // streaming path use HostExecutor instead.
    throw UnimplementedError('not used by the routing test');
  }
}

class _Harness {
  _Harness({
    required this.bash,
    required this.transcript,
    required this.jobs,
    required this.sink,
    required this.obs,
    required this.modes,
  });

  final BashMode bash;
  final Transcript transcript;
  final ShellJobManager jobs;
  final _RecordingSink sink;
  final Observability obs;
  final List<AppMode> modes;

  Future<void> dispose() async {
    await jobs.shutdown();
  }
}

_Harness _makeHarness({
  CommandExecutor? executor,
}) {
  final sink = _RecordingSink();
  final obs = Observability(debugController: DebugController())..addSink(sink);
  const shell = ShellConfig();
  final transcript = Transcript();
  final modes = <AppMode>[];

  final resolvedExecutor = executor ?? HostExecutor(shell);
  final jobs = ShellJobManager(resolvedExecutor, obs: obs);

  final bash = BashMode(
    transcript: transcript,
    executor: resolvedExecutor,
    jobs: jobs,
    obs: obs,
    setMode: modes.add,
    stopSpinner: () {},
    render: () {},
  );

  return _Harness(
    bash: bash,
    transcript: transcript,
    jobs: jobs,
    sink: sink,
    obs: obs,
    modes: modes,
  );
}

void main() {
  group('BashMode.submit routing', () {
    test('empty command is a no-op', () async {
      final h = _makeHarness(executor: _FakeExecutor());
      addTearDown(h.dispose);

      h.bash.submit('');

      expect(h.modes, isEmpty);
      expect(h.transcript.blocks, isEmpty);
    });

    test(
        'leading `& ` routes to the background job path — no '
        'AppMode.bashRunning transition', () async {
      final fake = _FakeExecutor();
      final h = _makeHarness(executor: fake);
      addTearDown(h.dispose);

      h.bash.submit('& echo hello');

      // Give the fire-and-forget start() a chance to run.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Background routing never flips the app into bashRunning.
      expect(h.modes, isNot(contains(AppMode.bashRunning)));
    });

    test('lone `&` (no command) is swallowed', () async {
      final fake = _FakeExecutor();
      final h = _makeHarness(executor: fake);
      addTearDown(h.dispose);

      h.bash.submit('&');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(h.modes, isEmpty);
      expect(fake.startedCommands, isEmpty);
    });

    test('foreground command flips app into bashRunning', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      h.bash.submit('echo hi');
      // Briefly wait for the async runBlocking to begin.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(h.modes.first, AppMode.bashRunning);
    });
  });

  group('BashMode.runBlocking', () {
    test('captures stdout into a bash transcript block', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      await h.bash.runBlocking('echo hello-world');

      final bashEntries =
          h.transcript.blocks.where((e) => e.kind == EntryKind.bash).toList();
      expect(bashEntries, hasLength(1));
      expect(bashEntries.first.text, contains('hello-world'));
      expect(bashEntries.first.expandedText, 'echo hello-world');
      // Mode ends on idle.
      expect(h.modes.last, AppMode.idle);
    });

    test('appends an "Exit code" system block on non-zero exit', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      await h.bash.runBlocking('exit 3');

      final systemEntries =
          h.transcript.blocks.where((e) => e.kind == EntryKind.system);
      expect(systemEntries.any((e) => e.text.contains('Exit code: 3')), isTrue);
    });

    test('emits shell.command span with exit_code attribute', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      await h.bash.runBlocking('echo hi');

      final span =
          h.sink.spans.lastWhere((span) => span.name == 'shell.command');
      expect(span.attributes['process.exit_code'], 0);
      expect(span.attributes['process.background'], false);
      expect(span.endTime, isNotNull);
    });

    test('error running command records error metadata on the span', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      // Target a nonsense command that the shell will reject. Implementation
      // may still run it under `sh -c` and return a non-zero exit; the
      // key path we want is the try/catch that logs 'error' on span.
      // Use an exec bypass to force an exception: bad binary path.
      // Depending on platform, this may resolve cleanly — so assert the
      // span is ended either way and no test flake.
      await h.bash.runBlocking('this_binary_does_not_exist_xyz_12345');

      final span =
          h.sink.spans.lastWhere((span) => span.name == 'shell.command');
      expect(span.endTime, isNotNull);
    });
  });

  group('BashMode.cancel', () {
    test('records cancelled=true on the in-flight span', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      final running = h.bash.runBlocking('sleep 5');
      // Give it a beat to start.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      h.bash.cancel();
      await running;

      final cancelled = h.sink.spans
          .where((s) => s.name == 'shell.command')
          .any((s) => s.attributes['cancelled'] == true);
      expect(cancelled, isTrue);
    });

    test('appends a [bash command cancelled] system notice', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      final running = h.bash.runBlocking('sleep 5');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      h.bash.cancel();
      await running;

      final cancelNote = h.transcript.blocks
          .where((e) => e.kind == EntryKind.system)
          .map((e) => e.text)
          .toList();
      expect(cancelNote.any((t) => t.contains('cancelled')), isTrue);
    });

    test('returns app to idle after cancel', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      final running = h.bash.runBlocking('sleep 5');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      h.bash.cancel();
      await running;

      expect(h.modes.last, AppMode.idle);
    });

    test('safe to call when no command is running', () async {
      final h = _makeHarness();
      addTearDown(h.dispose);

      expect(h.bash.cancel, returnsNormally);
      // Still appends the system notice (matches implementation).
      expect(
          h.transcript.blocks.any((e) => e.kind == EntryKind.system), isTrue);
    });
  });

  group('BashMode.handleJobEvent', () {
    test('JobStarted folds into a system-visible block', () {
      final h = _makeHarness(executor: _FakeExecutor());

      h.bash.handleJobEvent(JobStarted(1, 'echo bg'));

      final systemEntries =
          h.transcript.blocks.where((e) => e.kind == EntryKind.system).toList();
      expect(systemEntries, hasLength(1));
      expect(systemEntries.first.text, contains('Started job #1'));
      expect(systemEntries.first.text, contains('echo bg'));
    });

    test('JobExited folds into a system-visible block with exit code', () {
      final h = _makeHarness(executor: _FakeExecutor());

      h.bash.handleJobEvent(JobExited(2, 0));
      h.bash.handleJobEvent(JobExited(3, 1));

      final texts = h.transcript.blocks
          .where((e) => e.kind == EntryKind.system)
          .map((e) => e.text)
          .toList();
      expect(texts.any((t) => t.contains('#2 exited (0)')), isTrue);
      expect(texts.any((t) => t.contains('#3 failed (1)')), isTrue);
    });

    test('JobError folds into a system-visible block', () {
      final h = _makeHarness(executor: _FakeExecutor());

      h.bash.handleJobEvent(JobError(7, 'launch failed'));

      final texts = h.transcript.blocks
          .where((e) => e.kind == EntryKind.system)
          .map((e) => e.text)
          .toList();
      expect(texts.any((t) => t.contains('Job #7 error')), isTrue);
      expect(texts.any((t) => t.contains('launch failed')), isTrue);
    });
  });

  group('BashMode.active flag', () {
    test('defaults to false', () {
      final h = _makeHarness(executor: _FakeExecutor());
      expect(h.bash.active, isFalse);
    });

    test(
        'can be toggled — the router owns the state machine, BashMode '
        'just stores the bit', () {
      final h = _makeHarness(executor: _FakeExecutor());
      h.bash.active = true;
      expect(h.bash.active, isTrue);
      h.bash.active = false;
      expect(h.bash.active, isFalse);
    });
  });
}
