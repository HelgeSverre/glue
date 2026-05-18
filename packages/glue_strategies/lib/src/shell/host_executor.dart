import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/shell/command_executor.dart';
import 'package:glue_strategies/src/shell/shell_config.dart';

/// Runs commands directly on the host machine via the configured shell.
///
/// This is the default executor when Docker is disabled. Shell flags
/// (interactive, login) are determined by [ShellConfig.mode].
class HostExecutor implements CommandExecutor {
  final ShellConfig shellConfig;
  final RuntimeEventSink? eventSink;

  HostExecutor(this.shellConfig, {this.eventSink});

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final commandId = generateRuntimeCommandId();
    eventSink?.call(RuntimeCommandStarted(
      commandId: commandId,
      runtimeId: 'host',
      at: DateTime.now(),
      command: command,
      runtimeCwd: Directory.current.path,
    ));
    final started = DateTime.now();

    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);

    final Process process;
    try {
      process = await Process.start(exe, rest);
    } catch (e) {
      eventSink?.call(RuntimeCommandFailed(
        commandId: commandId,
        runtimeId: 'host',
        at: DateTime.now(),
        errorType: e.runtimeType.toString(),
        message: e.toString(),
      ));
      rethrow;
    }
    final stdoutFuture =
        process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture =
        process.stderr.transform(const SystemEncoding().decoder).join();

    final int exitCode;
    var cancelled = false;
    if (timeout == null) {
      exitCode = await process.exitCode;
    } else {
      exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        cancelled = true;
        return -1;
      });
    }

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (cancelled) {
      eventSink?.call(RuntimeCommandCancelled(
        commandId: commandId,
        runtimeId: 'host',
        at: DateTime.now(),
        reason: 'timeout',
      ));
    } else {
      eventSink?.call(RuntimeCommandCompleted(
        commandId: commandId,
        runtimeId: 'host',
        at: DateTime.now(),
        exitCode: exitCode,
        duration: DateTime.now().difference(started),
        stdoutBytes: stdout.length,
        stderrBytes: stderr.length,
      ));
    }

    return CaptureResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      runtimeId: 'host',
    );
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) async {
    final commandId = generateRuntimeCommandId();
    eventSink?.call(RuntimeCommandStarted(
      commandId: commandId,
      runtimeId: 'host',
      at: DateTime.now(),
      command: command,
      runtimeCwd: Directory.current.path,
    ));
    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);
    final process = await Process.start(exe, rest);
    final started = DateTime.now();
    final sink = eventSink;
    if (sink != null) {
      process.exitCode.then((code) {
        sink(RuntimeCommandCompleted(
          commandId: commandId,
          runtimeId: 'host',
          at: DateTime.now(),
          exitCode: code,
          duration: DateTime.now().difference(started),
        ));
      });
    }
    return RunningCommand(process);
  }
}
