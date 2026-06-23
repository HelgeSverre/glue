import 'package:glue_runtimes/src/common/bootstrap.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';

export 'package:glue_runtimes/src/common/bootstrap.dart' show BootstrapResult;

/// Sprites-specific glue around the shared [WorkspaceBootstrap]:
/// adapts [SpritesCliBase] to the [BootstrapBundleTransport] contract.
/// Sprites uploads bytes via base64 over `sprite exec`, which has a
/// practical cap of a few MB before WebSocket framing overhead and
/// shell-arg limits start to break things — so the bundle path is
/// only chosen for small repos. Larger repos fall back to
/// clone-from-remote (which requires a reachable origin).
class SpritesBootstrap {
  final SpritesCliBase cli;
  final String spriteName;
  final String sessionId;

  SpritesBootstrap({
    required this.cli,
    required this.spriteName,
    required this.sessionId,
  });

  Future<BootstrapResult> bootstrap({
    required String hostCwd,
    required String runtimeCwd,
  }) {
    return runWorkspaceBootstrap(
      exec: _SpritesBootstrapTransport(cli: cli, spriteName: spriteName),
      runtimeId: 'sprites',
      sessionId: sessionId,
      hostCwd: hostCwd,
      runtimeCwd: runtimeCwd,
    );
  }
}

class _SpritesBootstrapTransport implements BootstrapBundleTransport {
  final SpritesCliBase cli;
  final String spriteName;
  _SpritesBootstrapTransport({required this.cli, required this.spriteName});

  @override
  Future<BootstrapExecResult> run(String shellCommand) async {
    final r = await cli.execCapture(spriteName, shellCommand);
    return BootstrapExecResult(
      exitCode: r.exitCode,
      output: '${r.stdout}${r.stderr}',
    );
  }

  @override
  Future<void> uploadBytes(String runtimePath, List<int> bytes) =>
      cli.writeFileBytes(spriteName, runtimePath, bytes);

  // base64-over-shell exec is the bottleneck — the entire payload
  // goes through `sprite exec` as a single argv string, and the CLI's
  // WebSocket framing starts to break around a few MB. Pick a tight
  // cap; the fallback path covers larger repos via clone-from-remote.
  @override
  int get bundleSizeCapBytes => 3 * 1024 * 1024;
}
