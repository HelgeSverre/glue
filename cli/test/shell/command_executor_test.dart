import 'package:glue/src/shell/command_executor.dart';
import 'package:test/test.dart';

void main() {
  group('CaptureResult', () {
    test('stores exitCode, stdout, stderr', () {
      final r = CaptureResult(exitCode: 0, stdout: 'ok\n', stderr: '');
      expect(r.exitCode, 0);
      expect(r.stdout, 'ok\n');
      expect(r.stderr, '');
    });
  });
}
