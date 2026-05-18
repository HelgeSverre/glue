import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('CaptureResult', () {
    test('stores exitCode, stdout, stderr', () {
      final r = CaptureResult(exitCode: 0, stdout: 'ok\n', stderr: '');
      expect(r.exitCode, 0);
      expect(r.stdout, 'ok\n');
      expect(r.stderr, '');
    });

    test('defaults runtimeId to host when omitted', () {
      final r = CaptureResult(exitCode: 0, stdout: '', stderr: '');
      expect(r.runtimeId, 'host');
      expect(r.sessionId, isNull);
    });

    test('carries explicit runtimeId and sessionId when provided', () {
      final r = CaptureResult(
        exitCode: 0,
        stdout: '',
        stderr: '',
        runtimeId: 'docker',
        sessionId: 's-123',
      );
      expect(r.runtimeId, 'docker');
      expect(r.sessionId, 's-123');
    });
  });
}
