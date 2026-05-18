import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/modal/bootstrap.dart';
import 'package:glue_runtimes/src/modal/config.dart';
import 'package:glue_runtimes/src/modal/executor.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';
import 'package:glue_runtimes/src/modal/workspace.dart';

/// The top-level Modal runtime — owns one sandbox + sidecar for the
/// lifetime of a Glue session.
class ModalRuntime implements RuntimeSession {
  final ModalSidecarBase _sidecar;
  final ModalConfig _config;

  @override
  final String sandboxId;

  @override
  final CommandExecutor executor;

  @override
  final Workspace workspace;

  @override
  final String? bootstrapSha;

  @override
  final bool resumed;

  ModalRuntime._({
    required ModalSidecarBase sidecar,
    required ModalConfig config,
    required this.sandboxId,
    required this.executor,
    required this.workspace,
    required this.bootstrapSha,
    required this.resumed,
  })  : _sidecar = sidecar,
        _config = config;

  @override
  String get id => 'modal';

  /// Starts the python sidecar (which creates the modal sandbox),
  /// bootstraps the workspace, and returns a wired runtime.
  static Future<ModalRuntime> start({
    required ModalConfig config,
    required String hostCwd,
    String runtimeCwd = '/workspace',
    ModalSidecarBase? sidecarOverride,
    RuntimeEventSink? eventSink,
  }) async {
    final sidecar = sidecarOverride ?? ModalSidecar(config);
    try {
      await sidecar.start();
      final sandboxId = sidecar is ModalSidecar ? (sidecar.sandboxId ?? '') : '';

      final bootstrap = ModalBootstrap(sidecar: sidecar);
      final result = await bootstrap.bootstrap(
        hostCwd: hostCwd,
        runtimeCwd: runtimeCwd,
      );

      final mapping = WorkspaceMapping(
        hostCwd: hostCwd,
        runtimeCwd: runtimeCwd,
      );
      final executor = ModalExecutor(
        sidecar: sidecar,
        sandboxId: sandboxId,
        eventSink: eventSink,
      );
      final workspace = TransportWorkspace(
        fs: ModalFsTransport(sidecar: sidecar),
        mapping: mapping,
      );
      return ModalRuntime._(
        sidecar: sidecar,
        config: config,
        sandboxId: sandboxId,
        executor: executor,
        workspace: workspace,
        bootstrapSha: result.bootstrapSha,
        resumed: result.resumed,
      );
    } catch (e) {
      // Best-effort cleanup so we don't leak a long-lived sandbox on
      // bootstrap failure.
      try {
        await sidecar.shutdown();
      } catch (_) {}
      rethrow;
    }
  }

  /// Stops the sandbox and shuts the sidecar down.
  ///
  /// When [ModalConfig.deleteOnClose] is false, the sandbox is left
  /// running until its [ModalConfig.sandboxTimeoutSeconds] elapses.
  @override
  Future<void> close() async {
    if (_config.deleteOnClose) {
      await _sidecar.shutdown();
    }
  }
}
