import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/modal/sidecar.dart';

/// [CommandExecutor] backed by the modal sidecar.
///
/// Both synchronous capture (`runCapture`) and streaming background
/// jobs (`startStreaming`) are supported via the sidecar's JSON-RPC
/// protocol — sync ops block on a single response; streaming ops
/// emit per-chunk `stream_data` events keyed by `stream_id`.
class ModalExecutor implements CommandExecutor {
  final ModalSidecarBase sidecar;
  final String sandboxId;
  final String runtimeId;
  final RuntimeEventSink? eventSink;

  ModalExecutor({
    required this.sidecar,
    required this.sandboxId,
    this.runtimeId = 'modal',
    this.eventSink,
  });

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final commandId = generateRuntimeCommandId();
    eventSink?.call(
      RuntimeCommandStarted(
        commandId: commandId,
        runtimeId: runtimeId,
        at: DateTime.now(),
        command: command,
        runtimeCwd: '/workspace',
        sandboxId: sandboxId,
      ),
    );
    final started = DateTime.now();
    try {
      final result = await sidecar.execCapture(command, timeout: timeout);
      eventSink?.call(
        RuntimeCommandCompleted(
          commandId: commandId,
          runtimeId: runtimeId,
          at: DateTime.now(),
          exitCode: result.exitCode,
          duration: DateTime.now().difference(started),
          stdoutBytes: result.stdout.length,
          stderrBytes: result.stderr.length,
        ),
      );
      return CaptureResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        runtimeId: runtimeId,
        sessionId: sandboxId,
      );
    } catch (e) {
      eventSink?.call(
        RuntimeCommandFailed(
          commandId: commandId,
          runtimeId: runtimeId,
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
        runtimeId: runtimeId,
        at: DateTime.now(),
        command: command,
        runtimeCwd: '/workspace',
        sandboxId: sandboxId,
      ),
    );
    final started = DateTime.now();
    final handle = await sidecar.startStream(command);
    final sink = eventSink;
    if (sink != null) {
      handle.exitCode.then((code) {
        sink(
          RuntimeCommandCompleted(
            commandId: commandId,
            runtimeId: runtimeId,
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
