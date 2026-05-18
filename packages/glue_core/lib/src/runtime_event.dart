/// Narrow runtime-layer events emitted by [CommandExecutor]
/// implementations when a [RuntimeEventSink] is supplied.
///
/// These are deliberately smaller than the full `SessionEvent` variants
/// in `session_event.dart` — executors don't know about turn ids or
/// per-session sequence numbers. The harness consumes [RuntimeEvent]s
/// and translates them into the broader `RuntimeCommand*Event`s with
/// turn context attached.
///
/// Pattern-match with `switch`:
/// ```dart
/// switch (event) {
///   RuntimeCommandStarted(:final command) => print('▶ $command'),
///   RuntimeCommandCompleted(:final exitCode) => print('✓ exit=$exitCode'),
///   RuntimeCommandFailed(:final message) => print('✗ $message'),
///   RuntimeCommandCancelled(:final reason) => print('⨯ cancelled: $reason'),
/// }
/// ```
sealed class RuntimeEvent {
  /// Per-execution identifier. Stable across [RuntimeCommandStarted]
  /// → [RuntimeCommandCompleted] / [RuntimeCommandFailed] /
  /// [RuntimeCommandCancelled] for the same command.
  final String commandId;

  /// Adapter id: `'host'`, `'docker'`, `'daytona'`, `'sprites'`,
  /// `'modal'`.
  final String runtimeId;

  /// Wall-clock time the event was produced.
  final DateTime at;

  const RuntimeEvent({
    required this.commandId,
    required this.runtimeId,
    required this.at,
  });
}

/// A command has been dispatched and is starting.
class RuntimeCommandStarted extends RuntimeEvent {
  /// The command line as dispatched. Treat as a display string —
  /// emitters may truncate.
  final String command;

  /// The directory inside the runtime where the command will execute
  /// (`/workspace` for cloud/Docker; host cwd otherwise).
  final String runtimeCwd;

  /// Cloud-side per-session sandbox id (e.g. Daytona sandboxId, sprite
  /// name, Modal sandbox id). `null` for host.
  final String? sandboxId;

  const RuntimeCommandStarted({
    required super.commandId,
    required super.runtimeId,
    required super.at,
    required this.command,
    required this.runtimeCwd,
    this.sandboxId,
  });
}

/// A command finished normally with [exitCode]. Non-zero exit codes
/// are *not* errors — they're the program's own failure signal. Use
/// [RuntimeCommandFailed] for transport-level errors.
class RuntimeCommandCompleted extends RuntimeEvent {
  final int exitCode;
  final Duration duration;
  final int? stdoutBytes;
  final int? stderrBytes;

  const RuntimeCommandCompleted({
    required super.commandId,
    required super.runtimeId,
    required super.at,
    required this.exitCode,
    required this.duration,
    this.stdoutBytes,
    this.stderrBytes,
  });
}

/// A command failed at the transport / runtime layer (the runtime
/// couldn't run it at all, lost connection, etc.). Distinct from a
/// non-zero exit code, which is [RuntimeCommandCompleted].
class RuntimeCommandFailed extends RuntimeEvent {
  final String errorType;
  final String message;

  const RuntimeCommandFailed({
    required super.commandId,
    required super.runtimeId,
    required super.at,
    required this.errorType,
    required this.message,
  });
}

/// A command was cancelled by the harness (timeout, `/cancel`,
/// shutdown) before it finished.
class RuntimeCommandCancelled extends RuntimeEvent {
  final String reason;

  const RuntimeCommandCancelled({
    required super.commandId,
    required super.runtimeId,
    required super.at,
    required this.reason,
  });
}

/// Callback executors invoke for each [RuntimeEvent]. Construction is
/// guarded by a `sink != null` check, so producing events is free when
/// no sink is supplied (the default).
typedef RuntimeEventSink = void Function(RuntimeEvent);
