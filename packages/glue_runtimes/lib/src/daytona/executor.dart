import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/daytona/client.dart';
import 'package:glue_runtimes/src/daytona/running_command.dart';

/// [CommandExecutor] backed by Daytona's exec API.
///
/// All commands run inside the previously-created sandbox at the
/// runtime's cwd (which is `/workspace`).
class DaytonaExecutor implements CommandExecutor {
  final DaytonaClient client;
  final DaytonaSandbox sandbox;
  final String runtimeId;
  final RuntimeEventSink? eventSink;

  /// Identifier used for the long-lived background session that
  /// [startStreaming] dispatches commands into. The session is
  /// created lazily on the first streaming call.
  final String backgroundSessionId;

  bool _sessionCreated = false;

  DaytonaExecutor({
    required this.client,
    required this.sandbox,
    this.runtimeId = 'daytona',
    String? backgroundSessionId,
    this.eventSink,
  }) : backgroundSessionId =
           backgroundSessionId ??
           'glue-bg-${DateTime.now().microsecondsSinceEpoch}';

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
        sandboxId: sandbox.id,
      ),
    );
    final started = DateTime.now();
    try {
      final result = await client.execCapture(
        sandbox,
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
          stdoutBytes: result.result.length,
        ),
      );
      // Daytona returns a single combined output; we forward it as
      // stdout and leave stderr empty (see DaytonaRunningCommand for
      // the same convention).
      return CaptureResult(
        exitCode: result.exitCode,
        stdout: result.result,
        stderr: '',
        runtimeId: runtimeId,
        sessionId: sandbox.id,
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
        sandboxId: sandbox.id,
      ),
    );
    final started = DateTime.now();
    if (!_sessionCreated) {
      await client.createSession(sandbox, backgroundSessionId);
      _sessionCreated = true;
    }
    final sessionCmd = await client.executeSessionCommand(
      sandbox,
      backgroundSessionId,
      command,
      runAsync: true,
    );
    final handle = DaytonaRunningCommand(
      client: client,
      sandbox: sandbox,
      command: sessionCmd,
    );
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
