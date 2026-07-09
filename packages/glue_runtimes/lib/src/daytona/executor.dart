import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';

import 'package:glue_runtimes/src/common/transport_executor.dart';
import 'package:glue_runtimes/src/daytona/client.dart';
import 'package:glue_runtimes/src/daytona/running_command.dart';

/// [CommandExecutor] backed by Daytona's exec API.
///
/// All commands run inside the previously-created sandbox at the
/// runtime's cwd (which is `/workspace`). The runtime-event envelope
/// lives in the shared [TransportExecutor]; this class is just the
/// Daytona-specific [CaptureBackend].
class DaytonaExecutor implements CommandExecutor {
  final TransportExecutor _delegate;

  DaytonaExecutor({
    required DaytonaClient client,
    required DaytonaSandbox sandbox,
    String runtimeId = 'daytona',
    RuntimeEventSink? eventSink,
  }) : _delegate = TransportExecutor(
         backend: _DaytonaBackend(
           client: client,
           sandbox: sandbox,
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

/// Daytona-specific transport. Returns a single combined output stream
/// (stderr stays empty — see [DaytonaRunningCommand] for the same
/// convention) and creates a *fresh* background session per streaming
/// command (see [stream]).
class _DaytonaBackend implements CaptureBackend {
  final DaytonaClient client;
  final DaytonaSandbox sandbox;

  /// Monotonic suffix guaranteeing per-command session-id uniqueness
  /// even if two `stream()` calls land in the same microsecond.
  int _streamSeq = 0;

  _DaytonaBackend({
    required this.client,
    required this.sandbox,
    required this.runtimeId,
  });

  @override
  final String runtimeId;

  @override
  String get sandboxId => sandbox.id;

  @override
  bool get reportsStderr => false;

  @override
  Future<CaptureResult> capture(String command, {Duration? timeout}) async {
    final result = await client.execCapture(sandbox, command, timeout: timeout);
    // Daytona returns a single combined output; forward it as stdout and
    // leave stderr empty.
    return CaptureResult(
      exitCode: result.exitCode,
      stdout: result.result,
      stderr: '',
      runtimeId: runtimeId,
      sessionId: sandbox.id,
    );
  }

  @override
  Future<RunningCommandHandle> stream(String command) async {
    // One session per streaming command. A single shared session meant
    // that killing one background command (which deletes its parent
    // session) SIGTERMed every sibling, and the next stream() would
    // exec into a now-deleted session. A per-command session keeps
    // kills isolated; DaytonaRunningCommand deletes its own session on
    // completion or kill so they don't accumulate.
    final sessionId =
        'glue-bg-${DateTime.now().microsecondsSinceEpoch}-${_streamSeq++}';
    await client.createSession(sandbox, sessionId);
    final sessionCmd = await client.executeSessionCommand(
      sandbox,
      sessionId,
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
