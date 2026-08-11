import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  test(
    'parses reasoning summary, function call, artifact, and usage',
    () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {'type': 'response.reasoning_summary_text.delta', 'delta': 'Checking'},
        {
          'type': 'response.output_item.added',
          'item': {
            'type': 'function_call',
            'call_id': 'call_1',
            'name': 'read_file',
          },
        },
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'reasoning',
            'id': 'rs_1',
            'encrypted_content': 'opaque',
          },
        },
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'call_id': 'call_1',
            'name': 'read_file',
            'arguments': '{"path":"a.txt"}',
          },
        },
        {
          'type': 'response.completed',
          'response': {
            'usage': {
              'input_tokens': 100,
              'input_tokens_details': {'cached_tokens': 80},
              'output_tokens': 25,
              'output_tokens_details': {'reasoning_tokens': 10},
            },
          },
        },
      ]);

      final chunks = await OpenAiResponsesClient.parseStreamEvents(
        events,
      ).toList();
      expect(chunks.whereType<ThinkingDelta>().single.text, 'Checking');
      expect(chunks.whereType<ToolCallComplete>().single.toolCall.arguments, {
        'path': 'a.txt',
      });
      expect(chunks.whereType<ReasoningArtifactChunk>(), hasLength(1));
      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 20);
      expect(usage.cacheReadTokens, 80);
      expect(usage.reasoningTokens, 10);
    },
  );
}
