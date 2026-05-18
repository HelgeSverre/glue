import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_runtimes/src/daytona/client.dart';

/// [RunningCommandHandle] backed by Daytona's session+logs API.
///
/// Daytona doesn't expose a streaming HTTP exec; it provides a
/// long-lived session, a `/logs` endpoint that returns the
/// accumulated output, and a separate `/command/{cmdId}` status
/// endpoint that exposes `exitCode` once the command finishes. This
/// handle polls both: logs every cycle for new bytes, status only
/// when the logs haven't grown (to avoid hammering the status API).
///
/// **Stream separation:** Daytona's logs endpoint returns stdout
/// and stderr interleaved as a single stream. We forward everything
/// to [stdout] and leave [stderr] empty — callers should not rely
/// on stderr being populated for cloud runtimes.
///
/// **Kill semantics:** `kill(force: false)` deletes the parent
/// session, which sends SIGTERM to all running commands within it.
/// `kill(force: true)` additionally stops the entire sandbox via
/// [DaytonaClient.stopSandbox] — drastic (kills sibling commands and
/// renders the sandbox unusable) but matches the host-runtime
/// contract for forced termination during shutdown.
class DaytonaRunningCommand implements RunningCommandHandle {
  final DaytonaClient _client;
  final DaytonaSandbox _sandbox;
  final DaytonaSessionCommand _command;
  final Duration pollInterval;

  final _stdoutCtrl = StreamController<List<int>>.broadcast();
  final _stderrCtrl = StreamController<List<int>>.broadcast();
  final _exitCompleter = Completer<int>();

  bool _killed = false;
  bool _stopped = false;

  DaytonaRunningCommand({
    required DaytonaClient client,
    required DaytonaSandbox sandbox,
    required DaytonaSessionCommand command,
    this.pollInterval = const Duration(milliseconds: 250),
  })  : _client = client,
        _sandbox = sandbox,
        _command = command {
    _pump();
  }

  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;

  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  Future<void> kill({bool force = false}) async {
    if (_killed) return;
    _killed = true;
    try {
      await _client.deleteSession(_sandbox, _command.sessionId);
      if (force) {
        // Honour the force contract — at the host runtime, a SIGKILL
        // is unavoidable. The cloud equivalent is "terminate the
        // sandbox" since Daytona has no per-process kill. Drastic
        // but matches the documented escalation.
        await _client.stopSandbox(_sandbox.id);
      }
    } catch (_) {
      // Best-effort — pump will close once polling fails.
    }
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(-1);
    await _stop();
  }

  Future<void> _pump() async {
    var offset = 0;
    while (!_stopped) {
      try {
        final logs = await _client.getSessionCommandLogs(
          _sandbox,
          _command.sessionId,
          _command.commandId,
        );
        if (logs.length > offset) {
          final delta = logs.substring(offset);
          offset = logs.length;
          _stdoutCtrl.add(utf8.encode(delta));
        }
        // The logs endpoint has no completion signal — check the
        // status endpoint each cycle. Cheap (~100B JSON) and gives
        // us the exitCode the moment the command finishes.
        final status = await _client.getSessionCommandStatus(
          _sandbox,
          _command.sessionId,
          _command.commandId,
        );
        if (status.exitCode != null) {
          // Drain one more time in case the last logs poll raced
          // ahead of stdout being flushed.
          final finalLogs = await _client.getSessionCommandLogs(
            _sandbox,
            _command.sessionId,
            _command.commandId,
          );
          if (finalLogs.length > offset) {
            _stdoutCtrl.add(utf8.encode(finalLogs.substring(offset)));
          }
          if (!_exitCompleter.isCompleted) {
            _exitCompleter.complete(status.exitCode!);
          }
          await _stop();
          return;
        }
      } catch (e, st) {
        if (_killed) return;
        if (!_exitCompleter.isCompleted) {
          _exitCompleter.completeError(e, st);
        }
        await _stop();
        return;
      }
      if (_stopped) return;
      await Future.delayed(pollInterval);
    }
  }

  Future<void> _stop() async {
    if (_stopped) return;
    _stopped = true;
    if (!_exitCompleter.isCompleted) _exitCompleter.complete(0);
    await _stdoutCtrl.close();
    await _stderrCtrl.close();
  }
}
