import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';

/// [RunningCommandHandle] backed by a streaming exec on the modal
/// sidecar.
///
/// The sidecar emits async events keyed by `stream_id`:
///   - `stream_data` with `stream:"stdout"|"stderr", data:str`
///   - `stream_exit` with `exit_code:int|null`
///
/// Glue's [ModalSidecar] dispatches those events here via the
/// `onData`/`onExit` callbacks; this class owns the controllers and
/// the exit completer.
class ModalRunningCommand implements RunningCommandHandle {
  final String streamId;

  /// Sends a `stream_kill` request to the sidecar (SIGTERM via the
  /// recorded PID). Returns when the sidecar acks the kill — the
  /// actual `stream_exit` event arrives asynchronously after the
  /// inner process winds down.
  final Future<void> Function() _killer;

  /// Force-shutdown the entire sidecar + sandbox. Used by `kill(force:
  /// true)` to honour the host-runtime contract for forced
  /// termination — drastic (kills sibling streams) but the only way
  /// to guarantee the process is dead when SIGTERM is ignored.
  final Future<void> Function() _forceShutdown;

  final _stdoutCtrl = StreamController<List<int>>.broadcast();
  final _stderrCtrl = StreamController<List<int>>.broadcast();
  final _exitCompleter = Completer<int>();

  bool _killed = false;
  bool _closed = false;

  ModalRunningCommand({
    required this.streamId,
    required this._killer,
    required this._forceShutdown,
  });

  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;

  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  /// Called by the sidecar dispatcher when a `stream_data` event
  /// arrives for [streamId].
  void onData(String streamName, String text) {
    if (_closed) return;
    final bytes = utf8.encode(text);
    if (streamName == 'stderr') {
      _stderrCtrl.add(bytes);
    } else {
      _stdoutCtrl.add(bytes);
    }
  }

  /// Called by the sidecar dispatcher when `stream_exit` arrives.
  /// Closes the output streams and resolves [exitCode].
  void onExit(int? exitCode) {
    if (_closed) return;
    _closed = true;
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(exitCode ?? (_killed ? -1 : 0));
    }
    _stdoutCtrl.close();
    _stderrCtrl.close();
  }

  /// Forwards the kill request to the sidecar. With `force: false`
  /// (default) sends SIGTERM to the user-process PID; with `force:
  /// true` additionally terminates the entire sandbox so the kill
  /// is guaranteed even when SIGTERM is ignored — drastic but
  /// matches the host `RunningCommand` contract.
  @override
  Future<void> kill({bool force = false}) async {
    if (_killed) return;
    _killed = true;
    try {
      await _killer();
      if (force) await _forceShutdown();
    } catch (_) {
      // Sidecar may already be tearing down — onExit will close us.
    }
  }
}
