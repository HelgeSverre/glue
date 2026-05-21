import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/sprites/cli.dart';

/// [CommandExecutor] backed by the `sprite` CLI's exec subcommand.
class SpritesExecutor implements CommandExecutor {
  final SpritesCliBase cli;
  final String spriteName;
  final String runtimeId;
  final RuntimeEventSink? eventSink;

  SpritesExecutor({
    required this.cli,
    required this.spriteName,
    this.runtimeId = 'sprites',
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
        sandboxId: spriteName,
      ),
    );
    final started = DateTime.now();
    try {
      final result = await cli.execCapture(
        spriteName,
        command,
        timeout: timeout,
      );
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
        sessionId: spriteName,
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
        sandboxId: spriteName,
      ),
    );
    final started = DateTime.now();
    final process = await cli.execStream(spriteName, command);
    final sink = eventSink;
    if (sink != null) {
      process.exitCode.then((code) {
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
    return RunningCommand(process);
  }
}
