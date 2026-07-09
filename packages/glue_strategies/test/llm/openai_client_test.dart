import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

Future<List<LlmChunk>> drain(Stream<LlmChunk> s) => s.toList();

void main() {
  group('OpenAiClient.parseStreamEvents usage (H3)', () {
    test(
      'subtracts OpenAI cached_tokens from prompt_tokens for inputTokens',
      () async {
        final events = Stream<Map<String, dynamic>>.fromIterable([
          {
            'choices': <dynamic>[],
            'usage': {
              'prompt_tokens': 10000,
              'completion_tokens': 42,
              'prompt_tokens_details': {'cached_tokens': 8000},
            },
          },
        ]);

        final chunks = await drain(OpenAiClient.parseStreamEvents(events));
        final usage = chunks.whereType<UsageInfo>().single;

        // prompt_tokens is a SUPERSET of cached_tokens on OpenAI, so the
        // uncached input must exclude the cache reads.
        expect(usage.inputTokens, 2000);
        expect(usage.cacheReadTokens, 8000);
        expect(usage.outputTokens, 42);
      },
    );

    test('clamps to zero when cached_tokens exceeds prompt_tokens', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'choices': <dynamic>[],
          'usage': {
            'prompt_tokens': 100,
            'completion_tokens': 1,
            'prompt_tokens_details': {'cached_tokens': 500},
          },
        },
      ]);
      final chunks = await drain(OpenAiClient.parseStreamEvents(events));
      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 0);
      expect(usage.cacheReadTokens, 500);
    });

    test('no cache details leaves inputTokens == prompt_tokens', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'choices': <dynamic>[],
          'usage': {'prompt_tokens': 123, 'completion_tokens': 7},
        },
      ]);
      final chunks = await drain(OpenAiClient.parseStreamEvents(events));
      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 123);
      expect(usage.cacheReadTokens, isNull);
    });
  });

  group('OpenAiClient.parseStreamEvents tool calls (L17)', () {
    test('flushes accumulated tool calls when stream ends without a '
        'finish_reason chunk', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'function': {'name': 'read_file', 'arguments': '{"path":'},
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '"a.txt"}'},
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
        },
        // Stream ends here — no finish_reason == 'tool_calls' chunk arrives.
      ]);

      final chunks = await drain(OpenAiClient.parseStreamEvents(events));
      final completed = chunks.whereType<ToolCallComplete>().toList();
      expect(completed, hasLength(1));
      expect(completed.single.toolCall.name, 'read_file');
      expect(completed.single.toolCall.arguments, {'path': 'a.txt'});
    });

    test('defaults a missing tool-call delta index to 0 (no throw)', () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    // No 'index' key — some OpenAI-compatible servers omit it.
                    'id': 'call_x',
                    'function': {'name': 'ls', 'arguments': '{}'},
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
        },
      ]);

      final chunks = await drain(OpenAiClient.parseStreamEvents(events));
      final completed = chunks.whereType<ToolCallComplete>().toList();
      expect(completed, hasLength(1));
      expect(completed.single.toolCall.name, 'ls');
    });
  });
}
