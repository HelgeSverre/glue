import 'package:glue_runtimes/src/common/bootstrap.dart';
import 'package:glue_runtimes/src/common/runtime_exception.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';

export 'package:glue_runtimes/src/common/bootstrap.dart' show BootstrapResult;

/// Sprites-specific glue around the shared [WorkspaceBootstrap]:
/// adapts [SpritesCliBase] to the [BootstrapExec] contract. Sprites
/// run as root and `/workspace` is auto-writable, so no prep step
/// is needed.
class SpritesBootstrap {
  final SpritesCliBase cli;
  final String spriteName;

  SpritesBootstrap({required this.cli, required this.spriteName});

  Future<BootstrapResult> bootstrap({
    required String hostCwd,
    required String runtimeCwd,
  }) async {
    final ws = WorkspaceBootstrap(
      exec: _SpritesBootstrapExec(cli: cli, spriteName: spriteName),
    );
    try {
      return await ws.bootstrap(hostCwd: hostCwd, runtimeCwd: runtimeCwd);
    } on BootstrapException catch (e) {
      throw RuntimeApiException(
        runtimeId: 'sprites',
        statusCode: e.exitCode ?? 0,
        endpoint: 'bootstrap_${e.stage}',
        message: e.message,
        body: e.output,
      );
    }
  }
}

class _SpritesBootstrapExec implements BootstrapExec {
  final SpritesCliBase cli;
  final String spriteName;
  _SpritesBootstrapExec({required this.cli, required this.spriteName});

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    final r = await cli.execCapture(spriteName, shellCommand);
    return BootstrapExecResult(
      exitCode: r.exitCode,
      output: '${r.stdout}${r.stderr}',
    );
  }
}
