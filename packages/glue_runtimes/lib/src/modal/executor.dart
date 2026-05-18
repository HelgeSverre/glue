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

  ModalExecutor({
    required this.sidecar,
    required this.sandboxId,
    this.runtimeId = 'modal',
  });

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final result = await sidecar.execCapture(command, timeout: timeout);
    return CaptureResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      runtimeId: runtimeId,
      sessionId: sandboxId,
    );
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      sidecar.startStream(command);
}
