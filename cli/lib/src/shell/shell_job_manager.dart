import 'dart:async';
import 'dart:io';

import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/redaction.dart';
import 'package:glue/src/shell/command_executor.dart';
import 'package:glue/src/shell/line_ring_buffer.dart';
import 'package:glue/src/utils.dart';

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
  final ObservabilitySpan? traceSpan;

  ShellJob({
    required this.id,
    required this.command,
    required this.startTime,
    required this.process,
    required this.output,
    this.traceSpan,
  });
}

/// Manages the lifecycle of background shell jobs.
///
/// Each job's output is captured into a [LineRingBuffer] and status
/// transitions are broadcast as [JobEvent]s, so the UI can update in
/// real time without polling.
class ShellJobManager {
  final CommandExecutor executor;
  final Observability? _obs;

  int _nextId = 1;
  final _jobs = <int, ShellJob>{};
  final _events = StreamController<JobEvent>.broadcast();

  ShellJobManager(this.executor, {Observability? obs}) : _obs = obs;

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
    final span = _obs?.startSpan(
      'shell.job',
      kind: 'shell.job',
      attributes: {
        'shell.job.id': id,
        'process.command': redactBody(command, maxBytes: 8.kilobytes),
        'process.background': true,
      },
    );
    try {
      final running = await executor.startStreaming(command);
      final process = running.process;

      final job = ShellJob(
        id: id,
        command: command,
        startTime: DateTime.now(),
        process: process,
        output: LineRingBuffer(maxLines: 2000, maxBytes: 256.kilobytes),
        traceSpan: span,
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
          _endSpan(job, extra: {
            'process.exit_code': code,
            'shell.job.output_lines': job.output.lineCount,
            'shell.job.status': job.status.name,
          });
          _events.add(JobExited(id, code));
        } catch (e, st) {
          if (job.status == JobStatus.killed) return;
          job.status = JobStatus.failed;
          _endSpan(job, extra: {
            'shell.job.status': job.status.name,
            'error': true,
            'error.type': e.runtimeType.toString(),
            'error.message': e.toString(),
            'error.stack': st.toString(),
          });
          _events.add(JobError(id, e));
        }
      }());

      return job;
    } catch (e, st) {
      if (span != null && _obs != null) {
        _obs.endSpan(span, extra: {
          'shell.job.status': JobStatus.failed.name,
          'error': true,
          'error.type': e.runtimeType.toString(),
          'error.message': e.toString(),
          'error.stack': st.toString(),
        });
      }
      rethrow;
    }
  }

  ShellJob? getJob(int id) => _jobs[id];

  /// Sends SIGTERM to the job with the given [id].
  ///
  /// No-op if the job doesn't exist or has already exited.
  Future<void> kill(int id) async {
    final job = _jobs[id];
    if (job == null || job.status != JobStatus.running) return;
    job.status = JobStatus.killed;
    _endSpan(job, extra: {
      'shell.job.status': job.status.name,
      'cancelled': true,
      'shell.job.output_lines': job.output.lineCount,
    });
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
      _endSpan(j, extra: {
        'shell.job.status': j.status.name,
        'cancelled': true,
        'shell.job.output_lines': j.output.lineCount,
      });
      j.process.kill(ProcessSignal.sigterm);
    }
    if (running.isNotEmpty) {
      await Future.delayed(800.milliseconds);
      for (final j in running) {
        try {
          j.process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    await _events.close();
  }

  void _endSpan(ShellJob job, {required Map<String, dynamic> extra}) {
    final span = job.traceSpan;
    final obs = _obs;
    if (span == null || obs == null || span.endTime != null) return;
    obs.endSpan(span, extra: extra);
  }
}
