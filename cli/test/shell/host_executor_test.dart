import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('HostExecutor', () {
    late HostExecutor executor;

    setUp(() {
      executor = HostExecutor(const ShellConfig(executable: 'sh'));
    });

    test('runCapture captures stdout', () async {
      final result = await executor.runCapture('echo hello');
      expect(result.stdout.trim(), 'hello');
      expect(result.exitCode, 0);
    });

    test('runCapture captures stderr', () async {
      final result = await executor.runCapture('echo err >&2');
      expect(result.stderr.trim(), 'err');
    });

    test('runCapture returns non-zero exit code', () async {
      final result = await executor.runCapture('exit 42');
      expect(result.exitCode, 42);
    });

    test('runCapture times out', () async {
      final result = await executor.runCapture(
        'sleep 10',
        timeout: const Duration(milliseconds: 100),
      );
      expect(result.exitCode, -1);
    });

    test('startStreaming returns RunningCommand', () async {
      final cmd = await executor.startStreaming('echo streaming');
      final output =
          await cmd.stdout.transform(const SystemEncoding().decoder).join();
      final code = await cmd.exitCode;
      expect(output.trim(), 'streaming');
      expect(code, 0);
    });

    test('emits Started → Completed when given an event sink', () async {
      final events = <RuntimeEvent>[];
      final executor = HostExecutor(const ShellConfig(executable: 'sh'),
          eventSink: events.add);
      final result = await executor.runCapture('echo hi');
      expect(result.exitCode, 0);
      expect(events, hasLength(2));
      final started = events.first as RuntimeCommandStarted;
      expect(started.runtimeId, 'host');
      expect(started.command, 'echo hi');
      final completed = events.last as RuntimeCommandCompleted;
      expect(completed.commandId, started.commandId);
      expect(completed.exitCode, 0);
      expect(completed.stdoutBytes, greaterThan(0));
    });

    test('emits Cancelled when runCapture times out', () async {
      final events = <RuntimeEvent>[];
      final executor = HostExecutor(const ShellConfig(executable: 'sh'),
          eventSink: events.add);
      final result = await executor.runCapture(
        'sleep 10',
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.exitCode, -1);
      expect(events.last, isA<RuntimeCommandCancelled>());
      expect((events.last as RuntimeCommandCancelled).reason, 'timeout');
    });
  });
}
