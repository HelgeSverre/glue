import 'dart:async';
import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/anthropic_client.dart';

// A mock HTTP client is complex; test the SSE parsing logic directly.
void main() {
  group('AnthropicClient.parseStream', () {
    test('parses text deltas from SSE events', () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {'input_tokens': 10, 'output_tokens': 0}
          }
        }),
        _sseData({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''}
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Hello '}
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'world'}
        }),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
          'usage': {'output_tokens': 5}
        }),
        _sseData({'type': 'message_stop'}),
      ];
      final chunks = await AnthropicClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final textDeltas = chunks.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.text).join(), 'Hello world');

      final usage = chunks.whereType<UsageInfo>().toList();
      expect(usage, isNotEmpty);
    });

    test('parses tool use blocks', () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {'input_tokens': 10, 'output_tokens': 0}
          }
        }),
        _sseData({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'tc1',
            'name': 'read_file'
          }
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"path"'}
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': ': "main.dart"}'
          }
        }),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 15}
        }),
        _sseData({'type': 'message_stop'}),
      ];

      final chunks = await AnthropicClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallDelta>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });
  });
}

Map<String, dynamic> _sseData(Map<String, dynamic> payload) => payload;
