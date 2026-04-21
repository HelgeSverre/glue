import 'dart:io';

import 'package:glue/src/shell/host_executor.dart';
import 'package:glue/src/shell/shell_config.dart';
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
  });
}
