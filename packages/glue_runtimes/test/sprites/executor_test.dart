import 'package:glue_runtimes/src/sprites/cli.dart';
import 'package:glue_runtimes/src/sprites/executor.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('SpritesExecutor.runCapture', () {
    test('forwards exec result and tags runtimeId/sessionId', () async {
      final cli = FakeSpritesCli()
        ..execCaptureResults['echo hi'] = SpritesExecResult(
          exitCode: 0,
          stdout: 'hi\n',
          stderr: '',
        );
      final executor = SpritesExecutor(cli: cli, spriteName: 'my');
      final result = await executor.runCapture('echo hi');
      expect(result.exitCode, 0);
      expect(result.stdout, 'hi\n');
      expect(result.runtimeId, 'sprites');
      expect(result.sessionId, 'my');
    });

    test('propagates non-zero exit code transparently', () async {
      final cli = FakeSpritesCli()
        ..execCaptureResults['false'] = SpritesExecResult(
          exitCode: 1,
          stdout: '',
          stderr: '',
        );
      final executor = SpritesExecutor(cli: cli, spriteName: 'my');
      final result = await executor.runCapture('false');
      expect(result.exitCode, 1);
    });
  });
}
