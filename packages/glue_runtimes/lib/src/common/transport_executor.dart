import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

/// Narrow contract a cloud adapter implements so [TransportExecutor]
/// can own the entire [RuntimeEventSink] lifecycle (Started → Completed
/// / Failed envelope) uniformly across Daytona, Sprites, and Modal.
///
/// The backend is *only* the transport-specific bits:
/// - [capture] runs a synchronous command and shapes the adapter's
///   native result into a [CaptureResult]. Daytona forwards combined
///   output as stdout with empty stderr; Sprites/Modal carry stdout +
///   stderr separately — that distinction lives entirely in the
///   backend.
/// - [stream] starts a background command and returns its handle
///   (Daytona creates a session lazily here; Sprites/Modal hand back
///   a process/sidecar handle).
abstract class CaptureBackend {
  /// Adapter id used to label runtime events (`'daytona'`, `'sprites'`,
  /// `'modal'`).
  String get runtimeId;

  /// Per-session sandbox id surfaced on [RuntimeCommandStarted].
  String get sandboxId;

  /// Whether this backend distinguishes stderr from stdout. Daytona
  /// returns a single combined stream (stderr always empty), so it
  /// reports `false` and the [RuntimeCommandCompleted] event omits
  /// `stderrBytes`. Sprites/Modal report `true`.
  bool get reportsStderr;

  /// Runs [command] synchronously and returns the captured result.
  Future<CaptureResult> capture(String command, {Duration? timeout});

  /// Starts [command] as a background job and returns its handle.
  Future<RunningCommandHandle> stream(String command);
}

/// [CommandExecutor] that wraps a [CaptureBackend] with the shared
/// runtime-event envelope every cloud adapter needs:
///
/// - `runCapture` → [RuntimeCommandStarted], then [RuntimeCommandCompleted]
///   on success or [RuntimeCommandFailed] on a transport error (rethrown).
/// - `startStreaming` → [RuntimeCommandStarted], then a deferred
///   [RuntimeCommandCompleted] once the handle's `exitCode` resolves.
class TransportExecutor implements CommandExecutor {
  final CaptureBackend backend;
  final RuntimeEventSink? eventSink;

  TransportExecutor({required this.backend, this.eventSink});

  String get _runtimeId => backend.runtimeId;

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final commandId = generateRuntimeCommandId();
    eventSink?.call(
      RuntimeCommandStarted(
        commandId: commandId,
        runtimeId: _runtimeId,
        at: DateTime.now(),
        command: command,
        runtimeCwd: '/workspace',
        sandboxId: backend.sandboxId,
      ),
    );
    final started = DateTime.now();
    try {
      final result = await backend.capture(command, timeout: timeout);
      eventSink?.call(
        RuntimeCommandCompleted(
          commandId: commandId,
          runtimeId: _runtimeId,
          at: DateTime.now(),
          exitCode: result.exitCode,
          duration: DateTime.now().difference(started),
          stdoutBytes: result.stdout.length,
          stderrBytes: backend.reportsStderr ? result.stderr.length : null,
        ),
      );
      return result;
    } catch (e) {
      eventSink?.call(
        RuntimeCommandFailed(
          commandId: commandId,
          runtimeId: _runtimeId,
          at: DateTime.now(),
          errorType: e.runtimeType.toString(),
          message: e.toString(),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) async {
    final commandId = generateRuntimeCommandId();
    eventSink?.call(
      RuntimeCommandStarted(
        commandId: commandId,
        runtimeId: _runtimeId,
        at: DateTime.now(),
        command: command,
        runtimeCwd: '/workspace',
        sandboxId: backend.sandboxId,
      ),
    );
    final started = DateTime.now();
    final handle = await backend.stream(command);
    final sink = eventSink;
    if (sink != null) {
      handle.exitCode.then((code) {
        sink(
          RuntimeCommandCompleted(
            commandId: commandId,
            runtimeId: _runtimeId,
            at: DateTime.now(),
            exitCode: code,
            duration: DateTime.now().difference(started),
          ),
        );
      });
    }
    return handle;
  }
}
