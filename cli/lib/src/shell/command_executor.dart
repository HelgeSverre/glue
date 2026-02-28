import 'dart:io';

class CaptureResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  CaptureResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// A handle to a running shell process.
///
/// Provides direct access to [stdout], [stderr], and [exitCode] without
/// going through the underlying [Process]. Subclassed by [DockerRunningCommand]
/// to add container cleanup on kill.
class RunningCommand {
  final Process process;

  RunningCommand(this.process);

  Stream<List<int>> get stdout => process.stdout;
  Stream<List<int>> get stderr => process.stderr;
  Future<int> get exitCode => process.exitCode;

  /// Gracefully terminates the process with SIGTERM.
  ///
  /// Override this to perform additional cleanup (e.g. stopping a Docker
  /// container) before or after sending the signal.
  Future<void> kill() async {
    process.kill(ProcessSignal.sigterm);
  }
}

/// Abstraction for running shell commands either locally or inside a container.
///
/// See [HostExecutor] for local execution and [DockerExecutor] for sandboxed
/// Docker execution. Use [ExecutorFactory.create] to pick the right one based
/// on the current [DockerConfig].
abstract class CommandExecutor {
  /// Runs [command] and returns the captured stdout, stderr, and exit code.
  ///
  /// When [timeout] is provided and exceeded, the process is killed and
  /// the returned [CaptureResult.exitCode] will be `-1`.
  Future<CaptureResult> runCapture(String command, {Duration? timeout});

  /// Starts [command] and returns a handle for streaming its output.
  ///
  /// Prefer this over [runCapture] for long-running or interactive processes
  /// where you want to consume stdout/stderr incrementally.
  Future<RunningCommand> startStreaming(String command);
}
