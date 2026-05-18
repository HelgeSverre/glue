import 'package:glue_runtimes/src/common/bootstrap.dart';
import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';

export 'package:glue_runtimes/src/common/bootstrap.dart' show BootstrapResult;

/// Modal-specific glue around the shared [WorkspaceBootstrap]:
/// adapts [ModalSidecarBase] to the [BootstrapExec] contract.
/// Modal's default image runs as root and `/workspace` is freely
/// creatable, so no prep step is needed. The sidecar's image layer
/// already ensures `git` is installed.
class ModalBootstrap {
  final ModalSidecarBase sidecar;

  ModalBootstrap({required this.sidecar});

  Future<BootstrapResult> bootstrap({
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final ws = WorkspaceBootstrap(
      exec: _ModalBootstrapExec(sidecar: sidecar),
    );
    try {
      return await ws.bootstrap(hostCwd: hostCwd, runtimeCwd: runtimeCwd);
    } on BootstrapException catch (e) {
      throw RuntimeApiException(
        runtimeId: 'modal',
        endpoint: 'bootstrap_${e.stage}',
        message: '${e.message}: ${e.output ?? "no output"}',
      );
    }
  }
}

class _ModalBootstrapExec implements BootstrapExec {
  final ModalSidecarBase sidecar;
  _ModalBootstrapExec({required this.sidecar});

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    final r = await sidecar.execCapture(shellCommand);
    return BootstrapExecResult(
      exitCode: r.exitCode,
      output: '${r.stdout}${r.stderr}',
    );
  }
}
