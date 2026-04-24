import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/shell/shell_job_manager.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:test/test.dart';

class _RecordingSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

void main() {
  group('JobStatus', () {
    test('enum values exist', () {
      expect(
          JobStatus.values,
          containsAll([
            JobStatus.running,
            JobStatus.exited,
            JobStatus.failed,
            JobStatus.killed,
          ]));
    });
  });

  group('JobEvent sealed class', () {
    test('JobStarted holds id and command', () {
      final e = JobStarted(1, 'echo hi');
      expect(e.id, 1);
      expect(e.command, 'echo hi');
    });

    test('JobExited holds id and exitCode', () {
      final e = JobExited(1, 0);
      expect(e.id, 1);
      expect(e.exitCode, 0);
    });

    test('JobError holds id and error', () {
      final e = JobError(1, 'fail');
      expect(e.id, 1);
      expect(e.error, 'fail');
    });
  });

  group('ShellJobManager', () {
    late ShellJobManager manager;
    late _RecordingSink sink;

    setUp(() {
      sink = _RecordingSink();
      final obs = Observability(debugController: DebugController());
      obs.addSink(sink);
      manager = ShellJobManager(
        HostExecutor(const ShellConfig()),
        obs: obs,
      );
    });

    tearDown(() async {
      await manager.shutdown();
    });

    test('start creates a job with incremental id', () async {
      final job1 = await manager.start('echo hello');
      final job2 = await manager.start('echo world');
      expect(job1.id, 1);
      expect(job2.id, 2);
    });

    test('start emits JobStarted event', () async {
      final events = <JobEvent>[];
      manager.events.listen(events.add);
      await manager.start('echo hi');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.whereType<JobStarted>(), isNotEmpty);
    });

    test('job captures stdout in output buffer', () async {
      final job = await manager.start('echo hello');
      await Future.delayed(const Duration(milliseconds: 500));
      expect(job.output.dump(), contains('hello'));
    });

    test('emits JobExited on process completion', () async {
      final events = <JobEvent>[];
      manager.events.listen(events.add);
      await manager.start('echo done');
      await Future.delayed(const Duration(milliseconds: 500));
      final exits = events.whereType<JobExited>().toList();
      expect(exits, isNotEmpty);
      expect(exits.first.exitCode, 0);
      final span = sink.spans.lastWhere((span) => span.name == 'shell.job');
      expect(span.attributes['process.exit_code'], 0);
      expect(span.attributes['shell.job.status'], JobStatus.exited.name);
    });

    test('getJob returns job by id', () async {
      final job = await manager.start('echo hi');
      expect(manager.getJob(job.id), same(job));
    });

    test('getJob returns null for unknown id', () {
      expect(manager.getJob(999), isNull);
    });

    test('jobs returns all jobs sorted by id', () async {
      await manager.start('echo a');
      await manager.start('echo b');
      final jobs = manager.jobs;
      expect(jobs.length, 2);
      expect(jobs[0].id, lessThan(jobs[1].id));
    });

    test('kill sends signal and updates status', () async {
      final job = await manager.start('sleep 30');
      await Future.delayed(const Duration(milliseconds: 100));
      await manager.kill(job.id);
      await Future.delayed(const Duration(milliseconds: 500));
      expect(job.status,
          anyOf(JobStatus.killed, JobStatus.exited, JobStatus.failed));
      final span = sink.spans.lastWhere((span) => span.name == 'shell.job');
      expect(span.attributes['cancelled'], isTrue);
      expect(span.attributes['shell.job.status'], JobStatus.killed.name);
    });

    test('shutdown terminates all running jobs', () async {
      await manager.start('sleep 30');
      await manager.start('sleep 30');
      await Future.delayed(const Duration(milliseconds: 100));
      await manager.shutdown();
      for (final job in manager.jobs) {
        expect(job.status, isNot(JobStatus.running));
      }
    });
  });
}
