import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/sprites/cli.dart';

/// [CommandExecutor] backed by the `sprite` CLI's exec subcommand.
class SpritesExecutor implements CommandExecutor {
  final SpritesCliBase cli;
  final String spriteName;
  final String runtimeId;

  SpritesExecutor({
    required this.cli,
    required this.spriteName,
    this.runtimeId = 'sprites',
  });

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final result = await cli.execCapture(
      spriteName,
      command,
      timeout: timeout,
    );
    return CaptureResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      runtimeId: runtimeId,
      sessionId: spriteName,
    );
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) async {
    final process = await cli.execStream(spriteName, command);
    return RunningCommand(process);
  }
}
