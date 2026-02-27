import 'dart:io';

class CaptureResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  CaptureResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

class RunningCommand {
  final Process process;

  RunningCommand(this.process);

  Stream<List<int>> get stdout => process.stdout;
  Stream<List<int>> get stderr => process.stderr;
  Future<int> get exitCode => process.exitCode;

  Future<void> kill() async {
    process.kill(ProcessSignal.sigterm);
  }
}

abstract class CommandExecutor {
  Future<CaptureResult> runCapture(String command, {Duration? timeout});
  Future<RunningCommand> startStreaming(String command);
}
