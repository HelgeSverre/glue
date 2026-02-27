import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/openai_client.dart';

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

      final toolCalls = chunks.whereType<ToolCallDelta>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });
  });
}
