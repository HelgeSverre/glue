import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/context/context_estimator.dart';
import 'package:test/test.dart';

void main() {
  group('ContextEstimator', () {
    late ContextEstimator estimator;

    setUp(() => estimator = ContextEstimator());

    test('estimateRaw returns non-zero for non-empty messages', () {
      final messages = [Message.user('Hello, how are you?')];
      expect(estimator.estimateRaw(messages), greaterThan(0));
    });

    test('estimateRaw includes system prompt tokens', () {
      final messages = [Message.user('Hi')];
      final withoutSystem = estimator.estimateRaw(messages);
      final withSystem = estimator.estimateRaw(
        messages,
        systemPrompt: 'You are a helpful assistant with a long system prompt.',
      );
      expect(withSystem, greaterThan(withoutSystem));
    });

    test('estimate applies calibrationRatio', () {
      final messages = [Message.user('Hello')];
      estimator.calibrationRatio = 2.0;
      final raw = estimator.estimateRaw(messages);
      expect(estimator.estimate(messages), (raw * 2.0).round());
    });

    test('calibrate updates calibrationRatio with EMA', () {
      // Start at 1.0, actual is 2× the raw estimate.
      estimator.calibrate(100, 200); // ratio = 2.0
      // EMA: 0.7 * 1.0 + 0.3 * 2.0 = 1.3
      expect(estimator.calibrationRatio, closeTo(1.3, 0.001));
    });

    test('calibrate ignores zero estimates', () {
      estimator.calibrationRatio = 1.5;
      estimator.calibrate(0, 100);
      expect(estimator.calibrationRatio, 1.5);
      estimator.calibrate(100, 0);
      expect(estimator.calibrationRatio, 1.5);
    });

    test('resetCalibration returns ratio to 1.0', () {
      estimator.calibrationRatio = 1.8;
      estimator.resetCalibration();
      expect(estimator.calibrationRatio, 1.0);
    });

    test('tool call arguments and name are included in estimate', () {
      final messages = [
        Message.assistant(
          text: 'Let me check.',
          toolCalls: [
            ToolCall(
              id: 'tc1',
              name: 'read_file',
              arguments: {'path': '/some/long/file/path/to/estimate.dart'},
            ),
          ],
        ),
      ];
      // Should be non-zero and larger than just the text.
      final textOnly = [Message.assistant(text: 'Let me check.')];
      expect(
        estimator.estimateRaw(messages),
        greaterThan(estimator.estimateRaw(textOnly)),
      );
    });
  });
}
