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
  }) : backgroundSessionId = backgroundSessionId ??
            'glue-bg-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final result = await client.execCapture(
      sandbox,
      command,
      timeout: timeout,
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
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) async {
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
    return DaytonaRunningCommand(
      client: client,
      sandbox: sandbox,
      command: sessionCmd,
    );
  }
}
