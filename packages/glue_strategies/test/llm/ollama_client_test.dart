import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaClient.parseStreamEvents error lines (M9)', () {
    test('throws when an NDJSON error line arrives', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {'error': 'model runner has crashed'},
      ]);

      expect(
        () => OllamaClient.parseStreamEvents(events).toList(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('model runner has crashed'),
          ),
        ),
      );
    });

    test('throws even after emitting partial content', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'message': {'role': 'assistant', 'content': 'hello'},
          'done': false,
        },
        {'error': 'context canceled'},
      ]);

      expect(
        () => OllamaClient.parseStreamEvents(events).toList(),
        throwsA(isA<Exception>()),
      );
    });

    test('normal done chunk still yields UsageInfo', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'message': {'role': 'assistant', 'content': 'hi'},
          'done': false,
        },
        {'done': true, 'prompt_eval_count': 12, 'eval_count': 3},
      ]);
      final chunks = await OllamaClient.parseStreamEvents(events).toList();
      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 12);
      expect(usage.outputTokens, 3);
    });
  });
}
