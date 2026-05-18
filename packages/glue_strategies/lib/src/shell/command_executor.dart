import 'dart:io';

import 'package:glue_core/glue_core.dart';

/// The captured output of a completed shell command.
class CaptureResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  /// Identifier of the runtime that ran this command (e.g. `'host'`,
  /// `'docker'`, `'daytona'`). Used by the SessionEvent layer to label
  /// runtime command events. Defaults to `'host'` so existing call sites
  /// that don't yet thread this through still work.
  final String runtimeId;

  /// Session this command was associated with, if known. Optional in V1;
  /// populated by the harness in later work so runtime events can be
  /// correlated with a session.
  final String? sessionId;

  CaptureResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.runtimeId = 'host',
    this.sessionId,
  });
}

/// A handle to a running shell process.
///
/// {@category Shell Execution}
///
/// Implements [RunningCommandHandle] so harness consumers (e.g.
/// `ShellJobManager`) can manage background jobs uniformly across
/// runtimes. Subclassed by `DockerRunningCommand` to add container
/// cleanup on kill.
class RunningCommand implements RunningCommandHandle {
  final Process process;

  RunningCommand(this.process);

  @override
  Stream<List<int>> get stdout => process.stdout;

  @override
  Stream<List<int>> get stderr => process.stderr;

  @override
  Future<int> get exitCode => process.exitCode;

  /// Terminates the underlying process.
  ///
  /// With `force: false` (default) sends SIGTERM; with `force: true`
  /// sends SIGKILL. Overrides may perform additional cleanup (e.g.
  /// stopping a Docker container) before signalling.
  @override
  Future<void> kill({bool force = false}) async {
    process.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
  }
}

/// Abstraction for running shell commands either locally or inside a container.
///
/// See [HostExecutor] for local execution and [DockerExecutor] for sandboxed
/// Docker execution. Use [ExecutorFactory.create] to pick the right one based
/// on the current [DockerConfig].
///
/// Implementations may accept an optional [RuntimeEventSink] to emit
/// [RuntimeCommandStarted] / [RuntimeCommandCompleted] / [RuntimeCommandFailed]
/// / [RuntimeCommandCancelled] events around each command. Emission is
/// guarded so a `null` sink is free.
abstract class CommandExecutor {
  /// Runs [command] and returns the captured stdout, stderr, and exit code.
  ///
  /// When [timeout] is provided and exceeded, the process is killed and
  /// the returned [CaptureResult.exitCode] will be `-1`.
  Future<CaptureResult> runCapture(String command, {Duration? timeout});

  /// Starts [command] and returns a handle for streaming its output.
  ///
  /// Prefer this over [runCapture] for long-running or interactive processes
  /// where you want to consume stdout/stderr incrementally. Implementations
  /// return their own [RunningCommandHandle] subtype (e.g. [RunningCommand]
  /// for host/Docker, an HTTP-backed handle for cloud runtimes).
  Future<RunningCommandHandle> startStreaming(String command);
}

/// Generates a short opaque command id used to correlate runtime events
/// emitted around a single executor invocation. Format is `cmd-<rand>` —
/// not stable across processes, not a secret.
String generateRuntimeCommandId() {
  final n = DateTime.now().microsecondsSinceEpoch;
  return 'cmd-${n.toRadixString(36)}';
}
