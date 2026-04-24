import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/llm/ollama_client.dart';
import 'package:test/test.dart';

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

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.first.name, 'read_file');

      final toolCalls = chunks.whereType<ToolCallComplete>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');

      final startIdx = chunks.indexWhere((c) => c is ToolCallStart);
      final deltaIdx = chunks.indexWhere((c) => c is ToolCallComplete);
      expect(startIdx, lessThan(deltaIdx));
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

    // Parallel calls of the same tool in a single turn (e.g. two `read_file`s)
    // are a common agent pattern. Ollama's /api/chat does NOT use
    // `tool_call_id` — tool results are matched to tool calls by position
    // and `tool_name`. This test locks in two guarantees that keep that
    // matching safe:
    //   1. Each streamed tool call gets a unique synthesised id (so
    //      internal agent-core bookkeeping never conflates them).
    //   2. Arguments flow through unaltered (so positional ordering of
    //      outgoing tool results can be verified against inputs).
    test(
        'parallel calls of the same tool in one turn get distinct ids and '
        'preserve arguments', () async {
      final events = [
        {
          'model': 'qwen3-coder:30b',
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'a.dart'},
                }
              },
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'b.dart'},
                }
              },
            ],
          },
          'done': false,
        },
        {
          'model': 'qwen3-coder:30b',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 40,
          'eval_count': 12,
        },
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(2));
      expect(starts[0].name, 'read_file');
      expect(starts[1].name, 'read_file');
      // Distinct IDs — proves no collision in synthesised bookkeeping.
      expect(starts[0].id, isNot(equals(starts[1].id)));

      final completes = chunks.whereType<ToolCallComplete>().toList();
      expect(completes, hasLength(2));
      expect(completes[0].toolCall.arguments['path'], 'a.dart');
      expect(completes[1].toolCall.arguments['path'], 'b.dart');
      // Arguments did not cross-contaminate across the two calls.
    });
  });
}
