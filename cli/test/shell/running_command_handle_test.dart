import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('RunningCommandHandle (host)', () {
    late HostExecutor executor;

    setUp(() {
      executor = HostExecutor(const ShellConfig(executable: 'sh'));
    });

    test('startStreaming returns a RunningCommandHandle', () async {
      final handle = await executor.startStreaming('echo hello');
      expect(handle, isA<RunningCommandHandle>());
      final out = await handle.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      expect(out.trim(), 'hello');
      expect(await handle.exitCode, 0);
    });

    test('kill terminates a long-running command', () async {
      final handle = await executor.startStreaming('sleep 30');
      await Future.delayed(const Duration(milliseconds: 50));
      await handle.kill();
      final code = await handle.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -999,
      );
      expect(code, isNot(-999), reason: 'kill should terminate the process');
      expect(code, isNot(0));
    });

    test('kill(force: true) also terminates', () async {
      final handle = await executor.startStreaming('sleep 30');
      await Future.delayed(const Duration(milliseconds: 50));
      await handle.kill(force: true);
      final code = await handle.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -999,
      );
      expect(
        code,
        isNot(-999),
        reason: 'force kill should terminate the process',
      );
    });
  });
}
