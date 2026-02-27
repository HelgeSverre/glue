import 'dart:async';
import 'dart:io';

import 'command_executor.dart';
import 'shell_config.dart';

class HostExecutor implements CommandExecutor {
  final ShellConfig shellConfig;

  HostExecutor(this.shellConfig);

  @override
  Future<CaptureResult> runCapture(String command, {Duration? timeout}) async {
    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);

    final process = await Process.start(exe, rest);
    final stdoutFuture =
        process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture =
        process.stderr.transform(const SystemEncoding().decoder).join();

    final int exitCode;
    if (timeout == null) {
      exitCode = await process.exitCode;
    } else {
      exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill();
        return -1;
      });
    }

    return CaptureResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  }

  @override
  Future<RunningCommand> startStreaming(String command) async {
    final args = shellConfig.buildArgs(command);
    final exe = args.first;
    final rest = args.sublist(1);
    final process = await Process.start(exe, rest);
    return RunningCommand(process);
  }
}
