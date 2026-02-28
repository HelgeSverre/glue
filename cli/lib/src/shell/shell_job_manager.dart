import 'dart:async';
import 'dart:io';

import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/line_ring_buffer.dart';

enum JobStatus {
  running,

  /// Exit code 0.
  exited,

  /// Non-zero exit code or error.
  failed,

  /// Terminated by explicit kill request (vs process exit).
  killed
}

sealed class JobEvent {}

class JobStarted extends JobEvent {
  final int id;
  final String command;
  JobStarted(this.id, this.command);
}

class JobExited extends JobEvent {
  final int id;
  final int exitCode;
  JobExited(this.id, this.exitCode);
}

class JobError extends JobEvent {
  final int id;
  final Object error;
  JobError(this.id, this.error);
}

class ShellJob {
  final int id;
  final String command;
  final DateTime startTime;
  final Process process;

  /// Combined stdout and stderr.
  final LineRingBuffer output;

  JobStatus status = JobStatus.running;
  int? exitCode;

  ShellJob({
    required this.id,
    required this.command,
    required this.startTime,
    required this.process,
    required this.output,
  });
}

/// Tracks background jobs, captures their output, and emits [JobEvent]s.
class ShellJobManager {
  final CommandExecutor executor;

  int _nextId = 1;
  final _jobs = <int, ShellJob>{};
  final _events = StreamController<JobEvent>.broadcast();

  ShellJobManager(this.executor);

  Stream<JobEvent> get events => _events.stream;

  /// Sorted by ID.
  List<ShellJob> get jobs =>
      _jobs.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  /// Output is automatically captured into the job's [LineRingBuffer].
  Future<ShellJob> start(String command) async {
    final id = _nextId++;
    final running = await executor.startStreaming(command);
    final process = running.process;

    final job = ShellJob(
      id: id,
      command: command,
      startTime: DateTime.now(),
      process: process,
      output: LineRingBuffer(maxLines: 2000, maxBytes: 256 * 1024),
    );
    _jobs[id] = job;
    _events.add(JobStarted(id, command));

    process.stdout.transform(const SystemEncoding().decoder).listen(
          job.output.addText,
        );
    process.stderr.transform(const SystemEncoding().decoder).listen(
          job.output.addText,
        );

    unawaited(() async {
      try {
        final code = await process.exitCode;
        job.exitCode = code;
        if (job.status == JobStatus.killed) return;
        job.status = code == 0 ? JobStatus.exited : JobStatus.failed;
        _events.add(JobExited(id, code));
      } catch (e) {
        if (job.status == JobStatus.killed) return;
        job.status = JobStatus.failed;
        _events.add(JobError(id, e));
      }
    }());

    return job;
  }

  ShellJob? getJob(int id) => _jobs[id];

  /// Sends [ProcessSignal.sigterm].
  Future<void> kill(int id) async {
    final job = _jobs[id];
    if (job == null || job.status != JobStatus.running) return;
    job.status = JobStatus.killed;
    job.process.kill(ProcessSignal.sigterm);
  }

  /// Shuts down the manager, killing all running jobs.
  ///
  /// It first sends [ProcessSignal.sigterm] and then [ProcessSignal.sigkill]
  /// after a short delay if processes are still running.
  Future<void> shutdown() async {
    final running =
        _jobs.values.where((j) => j.status == JobStatus.running).toList();
    for (final j in running) {
      j.status = JobStatus.killed;
      j.process.kill(ProcessSignal.sigterm);
    }
    if (running.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 800));
      for (final j in running) {
        try {
          j.process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    await _events.close();
  }
}
