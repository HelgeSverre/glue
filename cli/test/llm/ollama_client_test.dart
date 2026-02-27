import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/ollama_client.dart';

void main() {
  group('OllamaClient.parseStream', () {
    test('parses text deltas from streaming JSON', () async {
      final events = [
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': 'Hello '},
          'done': false
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': 'world'},
          'done': false
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 26,
          'eval_count': 10
        },
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');

      final usage = chunks.whereType<UsageInfo>().toList();
      expect(usage, hasLength(1));
      expect(usage.first.inputTokens, 26);
      expect(usage.first.outputTokens, 10);
    });

    test('parses tool calls', () async {
      final events = [
        {
          'model': 'llama3.2',
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'main.dart'},
                }
              }
            ]
          },
          'done': false,
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 20,
          'eval_count': 15
        },
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallDelta>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });
  });

  group('Ollama message mapping', () {
    test('tool result uses tool name not call ID', () {
      final msg = Message.toolResult(
        callId: 'ollama_tc_1',
        content: 'file contents',
        toolName: 'read_file',
      );
      expect(msg.toolName, 'read_file');
      expect(msg.toolCallId, 'ollama_tc_1');
    });
  });
}
