import 'dart:convert';

import 'package:glue_runtimes/src/modal/executor.dart';
import 'package:glue_runtimes/src/modal/running_command.dart';
import 'package:glue_runtimes/src/modal/sidecar.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('ModalExecutor.runCapture', () {
    test('forwards exec result and tags runtimeId/sessionId', () async {
      final sidecar = FakeModalSidecar()
        ..execResults['echo hi'] = ModalExecResult(
          exitCode: 0,
          stdout: 'hi\n',
          stderr: '',
        );
      final executor = ModalExecutor(sidecar: sidecar, sandboxId: 'sb-modal-1');
      final r = await executor.runCapture('echo hi');
      expect(r.exitCode, 0);
      expect(r.stdout, 'hi\n');
      expect(r.runtimeId, 'modal');
      expect(r.sessionId, 'sb-modal-1');
    });

    test(
      'startStreaming returns a handle that emits stream_data + exits',
      () async {
        final sidecar = FakeModalSidecar()
          ..streamScripts.add((
            stdout: ['line_1\n', 'line_2\n'],
            stderr: ['err\n'],
            exitCode: 7,
          ));
        final executor = ModalExecutor(sidecar: sidecar, sandboxId: 'sb-1');
        final handle = await executor.startStreaming(
          'echo line_1 && echo line_2',
        );
        // Attach BOTH listeners + the exit future synchronously
        // BEFORE awaiting any of them. Broadcast streams drop events
        // for listeners that attach after the data has flushed.
        final outFut = handle.stdout
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 2));
        final errFut = handle.stderr
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 2));
        final exitFut = handle.exitCode.timeout(const Duration(seconds: 2));
        expect(await outFut, 'line_1\nline_2\n');
        expect(await errFut, 'err\n');
        expect(await exitFut, 7);
      },
    );

    test(
      'streaming handle kill is best-effort + still resolves exitCode',
      () async {
        final sidecar = FakeModalSidecar()
          ..streamScripts.add((stdout: [], stderr: [], exitCode: 0));
        final executor = ModalExecutor(sidecar: sidecar, sandboxId: 'sb-1');
        final handle = await executor.startStreaming('sleep 99');
        await handle.kill();
        // Fake schedules exit microtask immediately — should resolve.
        expect(await handle.exitCode.timeout(const Duration(seconds: 1)), 0);
      },
    );

    test('kill(force: true) triggers the sidecar forceShutdown', () async {
      var shutdownCalled = false;
      // Bypass the fake's synthetic startStream — hand-roll a
      // ModalRunningCommand so we can inspect the forceShutdown
      // callback directly.
      final cmd = ModalRunningCommand(
        streamId: 's-test',
        killer: () async {},
        forceShutdown: () async {
          shutdownCalled = true;
        },
      );
      await cmd.kill(force: true);
      expect(
        shutdownCalled,
        isTrue,
        reason: 'force-kill must terminate the sidecar/sandbox',
      );
    });
  });
}
