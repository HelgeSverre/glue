import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/message_mapper.dart';

void main() {
  final messages = [
    Message.user('hello'),
    Message.assistant(text: 'hi there', toolCalls: [
      ToolCall(id: 'tc1', name: 'read_file', arguments: {'path': 'f.txt'}),
    ]),
    Message.toolResult(callId: 'tc1', content: 'file contents'),
  ];

  group('AnthropicMessageMapper', () {
    test('maps user message', () {
      final mapper = AnthropicMessageMapper();
      final result =
          mapper.mapMessages(messages, systemPrompt: 'You are Glue.');
      // System prompt is returned separately.
      expect(result.systemPrompt, 'You are Glue.');
      expect(result.messages.first['role'], 'user');
    });

    test('maps tool result as user role', () {
      final mapper = AnthropicMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final toolResultMsg = result.messages.last;
      expect(toolResultMsg['role'], 'user');
      expect(toolResultMsg['content'], isList);
      final block = (toolResultMsg['content'] as List).first as Map;
      expect(block['type'], 'tool_result');
      expect(block['tool_use_id'], 'tc1');
    });
  });

  group('OpenAiMessageMapper', () {
    test('prepends system message', () {
      final mapper = OpenAiMessageMapper();
      final result =
          mapper.mapMessages(messages, systemPrompt: 'You are Glue.');
      expect(result.messages.first['role'], 'system');
      expect(result.messages.first['content'], 'You are Glue.');
    });

    test('serializes tool call arguments as JSON string', () {
      final mapper = OpenAiMessageMapper();
      final messages = [
        Message.assistant(
          text: '',
          toolCalls: [
            ToolCall(
                id: 'tc1', name: 'read_file', arguments: {'path': '/foo.txt'}),
          ],
        ),
      ];
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final assistantMsg = result.messages.last;
      final toolCall = (assistantMsg['tool_calls'] as List).first as Map;
      final fn = toolCall['function'] as Map;
      final args = fn['arguments'] as String;
      // Must be valid JSON, not Dart Map.toString()
      expect(args, '{"path":"/foo.txt"}');
    });

    test('maps tool result as tool role', () {
      final mapper = OpenAiMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final toolResultMsg = result.messages.last;
      expect(toolResultMsg['role'], 'tool');
      expect(toolResultMsg['tool_call_id'], 'tc1');
    });
  });
}
