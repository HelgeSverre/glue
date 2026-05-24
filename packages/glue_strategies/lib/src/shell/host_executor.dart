import 'dart:io';

import 'package:glue_core/glue_core.dart';

import 'package:glue_strategies/src/shell/command_events.dart';
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
    eventSink.emitStarted(
      commandId: commandId,
      runtimeId: 'host',
      command: command,
      runtimeCwd: Directory.current.path,
    );
    final started = DateTime.now();

    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);

    final process = await _startProcess(exe, rest, commandId);
    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();

    final exitCode = await waitForExit(process, timeout);
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;

    if (exitCode == -1) {
      eventSink.emitCancelled(
        commandId: commandId,
        runtimeId: 'host',
        reason: 'timeout',
      );
    } else {
      eventSink.emitCompleted(
        commandId: commandId,
        runtimeId: 'host',
        exitCode: exitCode,
        duration: DateTime.now().difference(started),
        stdoutBytes: stdout.length,
        stderrBytes: stderr.length,
      );
    }

    return CaptureResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      runtimeId: 'host',
    );
  }

  Future<Process> _startProcess(String exe, List<String> rest, String commandId) async {
    try {
      return await Process.start(exe, rest);
    } catch (e) {
      eventSink.emitFailed(
        commandId: commandId,
        runtimeId: 'host',
        errorType: e.runtimeType.toString(),
        message: e.toString(),
      );
      rethrow;
    }
  }

  @override
  Future<RunningCommandHandle> startStreaming(String command) async {
    final commandId = generateRuntimeCommandId();
    eventSink.emitStarted(
      commandId: commandId,
      runtimeId: 'host',
      command: command,
      runtimeCwd: Directory.current.path,
    );
    final started = DateTime.now();
    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);
    final process = await Process.start(exe, rest);
    eventSink.monitorStreamExit(
      process: process,
      commandId: commandId,
      runtimeId: 'host',
      started: started,
    );
    return RunningCommand(process);
  }
}
