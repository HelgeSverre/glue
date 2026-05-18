/// An abstract handle to a running command in a runtime.
///
/// Implementations live in the strategies layer (e.g. process-backed
/// `RunningCommand` for host/Docker, HTTP-backed handles for cloud
/// runtimes). Consumers in the harness (`ShellJobManager`) depend only
/// on this interface so they can manage background jobs uniformly
/// regardless of where the command actually runs.
abstract class RunningCommandHandle {
  /// Stdout bytes from the running command.
  Stream<List<int>> get stdout;

  /// Stderr bytes from the running command.
  Stream<List<int>> get stderr;

  /// Resolves with the process exit code once the command finishes.
  Future<int> get exitCode;

  /// Terminates the running command.
  ///
  /// With [force] false (default), sends a polite signal (SIGTERM /
  /// graceful cancel). With [force] true, escalates to an immediate kill
  /// (SIGKILL / hard-stop). The shutdown path typically calls [kill]
  /// once politely, waits briefly, then calls [kill] with `force: true`
  /// for any commands still alive.
  Future<void> kill({bool force = false});
}
