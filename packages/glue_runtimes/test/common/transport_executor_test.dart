import 'dart:async';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue_runtimes/src/common/transport_executor.dart';
import 'package:test/test.dart';

/// A [RunningCommandHandle] whose [exitCode] resolves with an *error* —
/// mirrors [DaytonaRunningCommand] completing its exit completer with an
/// error when a transient logs/status HTTP poll fails.
class _ErroringHandle implements RunningCommandHandle {
  final _exit = Completer<int>();

  _ErroringHandle() {
    // Complete asynchronously so the `.then/.onError` chain in
    // TransportExecutor is what observes the error.
    scheduleMicrotask(() {
      _exit.completeError(StateError('transient poll failure'));
    });
  }

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> kill({bool force = false}) async {}
}

/// A [RunningCommandHandle] that completes its exit code normally.
class _NormalHandle implements RunningCommandHandle {
  final int code;
  _NormalHandle(this.code);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => Future.value(code);

  @override
  Future<void> kill({bool force = false}) async {}
}

class _FakeBackend implements CaptureBackend {
  final RunningCommandHandle handle;
  _FakeBackend(this.handle);

  @override
  String get runtimeId => 'fake';

  @override
  String get sandboxId => 'sb-fake';

  @override
  bool get reportsStderr => false;

  @override
  Future<CaptureResult> capture(String command, {Duration? timeout}) async =>
      CaptureResult(exitCode: 0, stdout: '', stderr: '', runtimeId: 'fake');

  @override
  Future<RunningCommandHandle> stream(String command) async => handle;
}

void main() {
  group('TransportExecutor.startStreaming', () {
    test('when handle.exitCode resolves with an error, emits a failure event '
        'instead of leaking an unhandled zone error', () async {
      // Regression for H14: the `.then` on handle.exitCode had no
      // onError, so an error completion became an unhandled async
      // error — fatal to the isolate. If unhandled, the surrounding
      // test zone fails; a passing test proves the error is handled.
      final events = <RuntimeEvent>[];
      final executor = TransportExecutor(
        backend: _FakeBackend(_ErroringHandle()),
        eventSink: events.add,
      );
      await executor.startStreaming('some-command');

      // Give the errored exitCode future time to propagate.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        events.whereType<RuntimeCommandStarted>(),
        hasLength(1),
        reason: 'startStreaming always emits a Started event',
      );
      final failed = events.whereType<RuntimeCommandFailed>().toList();
      expect(
        failed,
        hasLength(1),
        reason: 'the errored exitCode must surface as a Failed event',
      );
      expect(failed.single.message, contains('transient poll failure'));
    });

    test('emits Completed when exitCode resolves normally', () async {
      final events = <RuntimeEvent>[];
      final executor = TransportExecutor(
        backend: _FakeBackend(_NormalHandle(7)),
        eventSink: events.add,
      );
      await executor.startStreaming('cmd');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final completed = events.whereType<RuntimeCommandCompleted>().toList();
      expect(completed, hasLength(1));
      expect(completed.single.exitCode, 7);
    });
  });
}
