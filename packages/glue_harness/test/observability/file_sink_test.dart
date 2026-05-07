import 'dart:io';

import 'package:glue_harness/glue_harness.dart';
import 'package:test/test.dart';

void main() {
  group('FileSink', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('glue_file_sink_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('onSpan after close does not throw', () async {
      final sink = FileSink(logsDir: tempDir.path);
      await sink.close();

      final span = ObservabilitySpan(name: 'late.span', kind: 'internal')
        ..end();

      expect(() => sink.onSpan(span), returnsNormally);
    });

    test('flush after close does not throw', () async {
      final sink = FileSink(logsDir: tempDir.path);
      await sink.close();

      expect(sink.flush, returnsNormally);
    });

    test(
      'reproduces shutdown ordering crash: endSpan after Observability.close',
      () async {
        final obs = Observability(debugController: DebugController());
        obs.addSink(FileSink(logsDir: tempDir.path));

        await obs.close();

        final span = obs.startSpan('session.close');
        expect(() => obs.endSpan(span), returnsNormally);
      },
    );
  });
}
