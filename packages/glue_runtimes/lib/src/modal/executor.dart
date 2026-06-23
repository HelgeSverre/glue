import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/common/transport_executor.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';

/// [CommandExecutor] backed by the modal sidecar.
///
/// Both synchronous capture (`runCapture`) and streaming background
/// jobs (`startStreaming`) are supported via the sidecar's JSON-RPC
/// protocol — sync ops block on a single response; streaming ops
/// emit per-chunk `stream_data` events keyed by `stream_id`. The
/// runtime-event envelope lives in the shared [TransportExecutor];
/// this class is just the Modal-specific [CaptureBackend].
class ModalExecutor implements CommandExecutor {
  final TransportExecutor _delegate;

  ModalExecutor({
    required ModalSidecarBase sidecar,
    required String sandboxId,
    String runtimeId = 'modal',
    RuntimeEventSink? eventSink,
  }) : _delegate = TransportExecutor(
         backend: _ModalBackend(
           sidecar: sidecar,
           sandboxId: sandboxId,
           runtimeId: runtimeId,
         ),
         eventSink: eventSink,
       );

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) =>
      _delegate.runCapture(command, timeout: timeout);

  @override
  Future<RunningCommandHandle> startStreaming(String command) =>
      _delegate.startStreaming(command);
}

class _ModalBackend implements CaptureBackend {
  final ModalSidecarBase sidecar;

  _ModalBackend({
    required this.sidecar,
    required this.sandboxId,
    required this.runtimeId,
  });

  @override
  final String runtimeId;

  @override
  final String sandboxId;

  @override
  bool get reportsStderr => true;

  @override
  Future<CaptureResult> capture(String command, {Duration? timeout}) async {
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
  Future<RunningCommandHandle> stream(String command) =>
      sidecar.startStream(command);
}
