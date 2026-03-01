import 'dart:async';
import 'dart:io';

import 'package:glue/src/dev/devtools.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/line_ring_buffer.dart';

enum JobStatus {
  running,

  /// The process finished successfully (exit code 0).
  exited,

  /// The process exited with a non-zero code, or threw before completing.
  failed,

  /// The user (or shutdown) explicitly killed the process — distinguished
  /// from [failed] so the UI can show "killed" instead of "error".
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

  /// Interleaved stdout and stderr output, capped by the ring buffer limits.
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

/// Manages the lifecycle of background shell jobs.
///
/// Each job's output is captured into a [LineRingBuffer] and status
/// transitions are broadcast as [JobEvent]s, so the UI can update in
/// real time without polling.
class ShellJobManager {
  final CommandExecutor executor;

  int _nextId = 1;
  final _jobs = <int, ShellJob>{};
  final _events = StreamController<JobEvent>.broadcast();

  ShellJobManager(this.executor);

  Stream<JobEvent> get events => _events.stream;

  /// All known jobs (running, exited, and killed), sorted by ID (oldest first).
  List<ShellJob> get jobs =>
      _jobs.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  /// Starts [command] as a background job and begins capturing its output.
  ///
  /// Returns immediately with the [ShellJob] handle. Output from both stdout
  /// and stderr is fed into the job's [LineRingBuffer], and a [JobStarted]
  /// event is emitted on [events].
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
    GlueDev.log('shell.job', 'started [$id]: $command');

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
        GlueDev.log('shell.job', 'exited [$id]: code=$code');
      } catch (e) {
        if (job.status == JobStatus.killed) return;
        job.status = JobStatus.failed;
        _events.add(JobError(id, e));
        GlueDev.log('shell.job', 'error [$id]: $e', level: 1000);
      }
    }());

    return job;
  }

  ShellJob? getJob(int id) => _jobs[id];

  /// Sends SIGTERM to the job with the given [id].
  ///
  /// No-op if the job doesn't exist or has already exited.
  Future<void> kill(int id) async {
    final job = _jobs[id];
    if (job == null || job.status != JobStatus.running) return;
    job.status = JobStatus.killed;
    job.process.kill(ProcessSignal.sigterm);
  }

  /// Tears down the manager, stopping all running jobs.
  ///
  /// Sends SIGTERM first and waits briefly for graceful exit, then follows
  /// up with SIGKILL for any stubborn processes. The [events] stream is
  /// closed after cleanup, so no further events will be emitted.
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
