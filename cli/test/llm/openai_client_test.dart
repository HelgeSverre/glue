import 'dart:async';

import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiClient.parseStream', () {
    test('parses text deltas', () async {
      final events = [
        {
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'Hello '}
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'world'}
            }
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'stop'}
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5}
        },
      ];
      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');
    });

    test('parses streaming tool calls', () async {
      final events = [
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'tc1',
                    'type': 'function',
                    'function': {'name': 'read_file', 'arguments': ''}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '{"path":'}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': ' "main.dart"}'}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'}
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 15}
        },
      ];

      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallComplete>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });

    test('emits ToolCallStart before ToolCallComplete', () async {
      final events = [
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'role': 'assistant',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'tc1',
                    'type': 'function',
                    'function': {'name': 'write_file', 'arguments': ''}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '{"path": "a.txt"}'}
                  }
                ]
              }
            }
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'tool_calls'}
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 10}
        },
      ];

      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.first.id, 'tc1');
      expect(starts.first.name, 'write_file');

      final startIdx = chunks.indexWhere((c) => c is ToolCallStart);
      final deltaIdx = chunks.indexWhere((c) => c is ToolCallComplete);
      expect(startIdx, lessThan(deltaIdx));
    });

    test('emits ThinkingDelta for delta.reasoning', () async {
      final events = [
        {
          'choices': [
            {'index': 0, 'delta': {'reasoning': 'reasoning step 1'}}
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {'reasoning': ' step 2'}}
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {'content': 'final answer'}}
          ]
        },
        {
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'stop'}
          ],
          'usage': {'prompt_tokens': 5, 'completion_tokens': 3},
        },
      ];

      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      expect(
        chunks.whereType<ThinkingDelta>().map((c) => c.text),
        ['reasoning step 1', ' step 2'],
      );
      expect(
        chunks.whereType<TextDelta>().map((c) => c.text),
        ['final answer'],
      );
    });

    test('emits ThinkingDelta for delta.reasoning_content (proxy variant)',
        () async {
      final events = [
        {
          'choices': [
            {'index': 0, 'delta': {'reasoning_content': 'hmm'}}
          ]
        },
      ];
      final chunks = await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();
      expect(chunks.whereType<ThinkingDelta>().map((c) => c.text), ['hmm']);
    });

    test('surfaces cached_tokens from prompt_tokens_details (native OpenAI)',
        () async {
      final events = [
        {
          'choices': [],
          'usage': {
            'prompt_tokens': 4096,
            'completion_tokens': 64,
            'prompt_tokens_details': {'cached_tokens': 3500},
          },
        },
      ];

      final usage = (await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList())
          .whereType<UsageInfo>()
          .single;

      expect(usage.inputTokens, 4096);
      expect(usage.outputTokens, 64);
      expect(usage.cacheReadTokens, 3500);
      expect(usage.cacheCreationTokens, isNull);
    });

    test('surfaces OpenRouter cache_write_tokens alongside cached_tokens',
        () async {
      // OpenRouter normalises the upstream Anthropic shape into
      // OpenAI-shaped `prompt_tokens_details.cached_tokens` plus a sibling
      // `cache_write_tokens`. We surface both into UsageInfo so cost
      // estimation can distinguish reads from writes.
      final events = [
        {
          'choices': [],
          'usage': {
            'prompt_tokens': 12000,
            'completion_tokens': 128,
            'prompt_tokens_details': {'cached_tokens': 9000},
            'cache_write_tokens': 1200,
          },
        },
      ];

      final usage = (await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList())
          .whereType<UsageInfo>()
          .single;

      expect(usage.cacheReadTokens, 9000);
      expect(usage.cacheCreationTokens, 1200);
    });

    test('falls back to Anthropic-shape fields when proxy forwards them',
        () async {
      final events = [
        {
          'choices': [],
          'usage': {
            'prompt_tokens': 8000,
            'completion_tokens': 50,
            'cache_read_input_tokens': 7500,
            'cache_creation_input_tokens': 400,
          },
        },
      ];

      final usage = (await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList())
          .whereType<UsageInfo>()
          .single;

      expect(usage.cacheReadTokens, 7500);
      expect(usage.cacheCreationTokens, 400);
    });

    test('leaves cache fields null when no caching info is reported', () async {
      final events = [
        {
          'choices': [],
          'usage': {'prompt_tokens': 200, 'completion_tokens': 10},
        },
      ];

      final usage = (await OpenAiClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList())
          .whereType<UsageInfo>()
          .single;

      expect(usage.cacheReadTokens, isNull);
      expect(usage.cacheCreationTokens, isNull);
    });
  });
}
