import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/common/transport_executor.dart';
import 'package:glue_runtimes/src/sprites/cli.dart';

/// [CommandExecutor] backed by the `sprite` CLI's exec subcommand. The
/// runtime-event envelope lives in the shared [TransportExecutor]; this
/// class is just the Sprites-specific [CaptureBackend].
class SpritesExecutor implements CommandExecutor {
  final TransportExecutor _delegate;

  SpritesExecutor({
    required SpritesCliBase cli,
    required String spriteName,
    String runtimeId = 'sprites',
    RuntimeEventSink? eventSink,
  }) : _delegate = TransportExecutor(
         backend: _SpritesBackend(
           cli: cli,
           spriteName: spriteName,
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

class _SpritesBackend implements CaptureBackend {
  final SpritesCliBase cli;
  final String spriteName;

  _SpritesBackend({
    required this.cli,
    required this.spriteName,
    required this.runtimeId,
  });

  @override
  final String runtimeId;

  @override
  String get sandboxId => spriteName;

  @override
  bool get reportsStderr => true;

  @override
  Future<CaptureResult> capture(String command, {Duration? timeout}) async {
    final result = await cli.execCapture(spriteName, command, timeout: timeout);
    return CaptureResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      runtimeId: runtimeId,
      sessionId: spriteName,
    );
  }

  @override
  Future<RunningCommandHandle> stream(String command) async {
    final process = await cli.execStream(spriteName, command);
    return RunningCommand(process);
  }
}
