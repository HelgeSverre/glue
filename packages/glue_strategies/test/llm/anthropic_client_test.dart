import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicClient.parseStreamEvents error events (M9)', () {
    test('throws when a mid-stream error event arrives', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'type': 'message_start',
          'message': {
            'usage': {'input_tokens': 10},
          },
        },
        {
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
        },
      ]);

      expect(
        () => AnthropicClient.parseStreamEvents(events).toList(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('overloaded_error'), contains('Overloaded')),
          ),
        ),
      );
    });

    test(
      'does not commit a partial turn: text before error still throws',
      () async {
        final events = Stream<Map<String, dynamic>>.fromIterable([
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'partial'},
          },
          {
            'type': 'error',
            'error': {'type': 'api_error', 'message': 'boom'},
          },
        ]);
        expect(
          () => AnthropicClient.parseStreamEvents(events).toList(),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
