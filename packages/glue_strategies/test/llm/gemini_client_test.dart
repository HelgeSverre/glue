import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiClient.parseStreamEvents error signals (M9)', () {
    test('throws on a blocked prompt (promptFeedback.blockReason)', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'promptFeedback': {'blockReason': 'SAFETY'},
        },
      ]);
      expect(
        () => GeminiClient.parseStreamEvents(events).toList(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('SAFETY'),
          ),
        ),
      );
    });

    test('throws on an abnormal candidate finishReason', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'candidates': [
            {'finishReason': 'RECITATION'},
          ],
        },
      ]);
      expect(
        () => GeminiClient.parseStreamEvents(events).toList(),
        throwsA(isA<Exception>()),
      );
    });

    test('a normal STOP finishReason does not throw', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'hello'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
          'usageMetadata': {'promptTokenCount': 5, 'candidatesTokenCount': 1},
        },
      ]);
      final chunks = await GeminiClient.parseStreamEvents(events).toList();
      expect(chunks.whereType<TextDelta>().single.text, 'hello');
      expect(chunks.whereType<UsageInfo>().single.inputTokens, 5);
    });
  });
}
