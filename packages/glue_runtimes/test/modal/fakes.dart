import 'dart:async';
import 'dart:convert';

import 'package:glue_runtimes/src/modal/running_command.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';

/// In-memory fake of [ModalSidecarBase] for unit tests.
class FakeModalSidecar implements ModalSidecarBase {
  final Map<String, ModalExecResult> execResults = {};
  final Map<String, List<int>> files = {};
  final Map<String, ModalStat> stats = {};

  bool available = true;
  bool started = false;
  bool shutdownCalled = false;
  final List<String> executedCommands = [];

  @override
  bool get isReady => started;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> shutdown() async {
    shutdownCalled = true;
    started = false;
  }

  @override
  Future<ModalExecResult> execCapture(
    String command, {
    Duration? timeout,
  }) async {
    executedCommands.add(command);
    return execResults[command] ??
        ModalExecResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<List<int>> readFile(String path) async => files[path] ?? const [];

  @override
  Future<void> writeFile(String path, List<int> bytes) async {
    files[path] = bytes;
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<bool> isDirectory(String path) async => false;

  @override
  Future<List<ModalFsEntry>> listDir(String path) async {
    final base = path.endsWith('/') ? path : '$path/';
    return files.keys
        .where((p) => p.startsWith(base))
        .map(
          (p) => ModalFsEntry(
            name: p.substring(base.length),
            isDirectory: false,
            size: files[p]!.length,
          ),
        )
        .toList();
  }

  @override
  Future<ModalStat?> stat(String path) async {
    final s = stats[path];
    if (s != null) return s;
    final f = files[path];
    if (f == null) return null;
    return ModalStat(size: f.length, isDirectory: false);
  }

  /// Maps the next-to-be-started stream to a canned (stdout, stderr,
  /// exitCode) script. Each entry is consumed in order.
  final List<({List<String> stdout, List<String> stderr, int exitCode})>
  streamScripts = [];

  int _nextStreamId = 0;

  @override
  Future<ModalRunningCommand> startStream(String command) async {
    executedCommands.add(command);
    final sid = 's${++_nextStreamId}';
    final cmd = ModalRunningCommand(
      streamId: sid,
      killer: () async {
        /* no-op */
      },
      forceShutdown: () async {
        /* no-op */
      },
    );
    final script = streamScripts.isNotEmpty
        ? streamScripts.removeAt(0)
        : (stdout: <String>[], stderr: <String>[], exitCode: 0);
    // Drive the canned script on the next event-loop tick so the
    // caller has a chance to attach listeners to the broadcast
    // streams. `Future.delayed(Duration.zero)` is a microtask
    // boundary the caller's `await sidecar.startStream(...)` will
    // settle through before this runs.
    Future.delayed(Duration.zero, () {
      for (final s in script.stdout) {
        cmd.onData('stdout', s);
      }
      for (final s in script.stderr) {
        cmd.onData('stderr', s);
      }
      cmd.onExit(script.exitCode);
    });
    return cmd;
  }

  /// Helper for tests that want to seed a UTF-8 text file.
  void seedTextFile(String path, String content) {
    files[path] = utf8.encode(content);
  }
}
