import 'package:test/test.dart';
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
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
      const mapper = AnthropicMessageMapper();
      final result =
          mapper.mapMessages(messages, systemPrompt: 'You are Glue.');
      // System prompt is returned separately.
      expect(result.systemPrompt, 'You are Glue.');
      expect(result.messages.first['role'], 'user');
    });

    test('maps tool result as user role', () {
      const mapper = AnthropicMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final toolResultMsg = result.messages.last;
      expect(toolResultMsg['role'], 'user');
      expect(toolResultMsg['content'], isList);
      final block = (toolResultMsg['content'] as List).first as Map;
      expect(block['type'], 'tool_result');
      expect(block['tool_use_id'], 'tc1');
    });

    test('tool_result without contentParts uses text string', () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'bash', arguments: {}),
        ]),
        Message.toolResult(
            callId: 'tc1', content: 'result text', toolName: 'bash'),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // assistant + tool_result = 2
      final content = result.messages[1]['content'] as List;
      final toolResultBlock = content[0] as Map<String, dynamic>;
      expect(toolResultBlock['content'], 'result text');
      expect(toolResultBlock['content'], isA<String>());
    });

    test('tool_result with contentParts containing images emits image blocks',
        () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'web_browser', arguments: {}),
        ]),
        Message.toolResult(
          callId: 'tc1',
          content: 'Screenshot captured.',
          toolName: 'web_browser',
          contentParts: [
            const TextPart('Screenshot captured.'),
            const ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
          ],
        ),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // assistant + tool_result = 2
      final outerContent = result.messages[1]['content'] as List;
      final toolResultBlock = outerContent[0] as Map<String, dynamic>;
      final content = toolResultBlock['content'] as List;
      expect(content.length, 2);
      final textBlock = content[0] as Map<String, dynamic>;
      final imageBlock = content[1] as Map<String, dynamic>;
      expect(textBlock['type'], 'text');
      expect(textBlock['text'], 'Screenshot captured.');
      expect(imageBlock['type'], 'image');
      final source = imageBlock['source'] as Map<String, dynamic>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/png');
      expect(source['data'], isNotEmpty);
    });

    test('tool_result with contentParts but no images uses text string', () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'bash', arguments: {}),
        ]),
        Message.toolResult(
          callId: 'tc1',
          content: 'just text',
          toolName: 'bash',
          contentParts: [const TextPart('just text')],
        ),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // assistant + tool_result = 2
      final content = result.messages[1]['content'] as List;
      final toolResultBlock = content[0] as Map<String, dynamic>;
      expect(toolResultBlock['content'], 'just text');
    });

    test('drops orphaned tool_result with no matching tool_use', () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.user('hello'),
        Message.assistant(
          text: 'I will read',
          toolCalls: [
            ToolCall(
                id: 'tc1', name: 'read_file', arguments: {'path': 'a.txt'}),
          ],
        ),
        Message.toolResult(callId: 'tc1', content: 'file contents'),
        // Orphaned: tc_stale references a tool_use not in the preceding assistant message.
        Message.toolResult(callId: 'tc_stale', content: 'stale result'),
        Message.assistant(text: 'Here is the summary'),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // user + assistant(tool_use) + tool_result(tc1) + assistant(text) = 4
      // The orphaned tool_result(tc_stale) should be dropped.
      expect(result.messages, hasLength(4));
      // Verify the kept tool_result is tc1.
      final toolResultMsg = result.messages[2];
      final block = (toolResultMsg['content'] as List).first as Map;
      expect(block['tool_use_id'], 'tc1');
    });

    test('drops tool_result after assistant message with no tool_calls', () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.user('hello'),
        // Assistant message without tool_calls (e.g. after session resume).
        Message.assistant(text: 'I read the file for you'),
        // This tool_result is orphaned because the preceding assistant has no tool_uses.
        Message.toolResult(callId: 'tc1', content: 'file contents'),
        Message.user('thanks'),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // user + assistant + user = 3 (tool_result dropped).
      expect(result.messages, hasLength(3));
      expect(result.messages[0]['role'], 'user');
      expect(result.messages[1]['role'], 'assistant');
      expect(result.messages[2]['role'], 'user');
    });

    test('keeps all tool_results when they match tool_uses', () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.user('do two things'),
        Message.assistant(
          text: '',
          toolCalls: [
            ToolCall(id: 'tc1', name: 'read_file', arguments: {}),
            ToolCall(id: 'tc2', name: 'write_file', arguments: {}),
          ],
        ),
        Message.toolResult(callId: 'tc1', content: 'result 1'),
        Message.toolResult(callId: 'tc2', content: 'result 2'),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // user + assistant + tool_result(tc1) + tool_result(tc2) = 4.
      expect(result.messages, hasLength(4));
    });

    test('drops only the orphaned result in a mixed batch', () {
      const mapper = AnthropicMessageMapper();
      final msgs = [
        Message.user('hello'),
        Message.assistant(
          text: '',
          toolCalls: [
            ToolCall(id: 'tc1', name: 'read_file', arguments: {}),
            ToolCall(id: 'tc2', name: 'write_file', arguments: {}),
          ],
        ),
        Message.toolResult(callId: 'tc1', content: 'ok'),
        Message.toolResult(callId: 'tc_orphan', content: 'orphan'),
        Message.toolResult(callId: 'tc2', content: 'ok'),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: '');
      // user + assistant + tc1 + tc2 = 4 (tc_orphan dropped).
      expect(result.messages, hasLength(4));
      final ids = result.messages
          .where((m) => m['role'] == 'user')
          .expand((m) => m['content'] as List)
          .where((c) => c is Map<String, dynamic> && c['type'] == 'tool_result')
          .map((c) => (c as Map<String, dynamic>)['tool_use_id'])
          .toList();
      expect(ids, ['tc1', 'tc2']);
    });
  });

  group('OpenAiMessageMapper', () {
    test('prepends system message', () {
      const mapper = OpenAiMessageMapper();
      final result =
          mapper.mapMessages(messages, systemPrompt: 'You are Glue.');
      expect(result.messages.first['role'], 'system');
      expect(result.messages.first['content'], 'You are Glue.');
    });

    test('serializes tool call arguments as JSON string', () {
      const mapper = OpenAiMessageMapper();
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
      const mapper = OpenAiMessageMapper();
      final result = mapper.mapMessages(messages, systemPrompt: '');
      final toolResultMsg = result.messages.last;
      expect(toolResultMsg['role'], 'tool');
      expect(toolResultMsg['tool_call_id'], 'tc1');
    });

    test('tool_result without contentParts uses text string', () {
      const mapper = OpenAiMessageMapper();
      final msgs = [
        Message.user('hi'),
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'bash', arguments: {}),
        ]),
        Message.toolResult(
            callId: 'tc1', content: 'result text', toolName: 'bash'),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: 'sys');
      // system + user + assistant + tool = 4
      expect(result.messages.length, 4);
      final toolMsg = result.messages[3];
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['content'], 'result text');
    });

    test('tool_result with images emits text-only tool + follow-up user image',
        () {
      const mapper = OpenAiMessageMapper();
      final msgs = [
        Message.user('hi'),
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'web_browser', arguments: {}),
        ]),
        Message.toolResult(
          callId: 'tc1',
          content: 'Screenshot captured.',
          toolName: 'web_browser',
          contentParts: [
            const TextPart('Screenshot captured.'),
            const ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
          ],
        ),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: 'sys');
      // system + user + assistant + tool + follow-up user = 5
      expect(result.messages.length, 5);
      // Tool result is text-only
      final toolMsg = result.messages[3];
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['content'], 'Screenshot captured.');
      // Follow-up user message has image
      final imageMsg = result.messages[4];
      expect(imageMsg['role'], 'user');
      expect(imageMsg['content'], isList);
      final parts = imageMsg['content'] as List;
      expect(parts.length, 2);
      final textPart = parts[0] as Map<String, dynamic>;
      final imagePart = parts[1] as Map<String, dynamic>;
      expect(textPart['type'], 'text');
      expect(imagePart['type'], 'image_url');
      final imageUrl = imagePart['image_url'] as Map<String, dynamic>;
      expect((imageUrl['url'] as String).startsWith('data:image/png;base64,'),
          isTrue);
    });

    test('tool_result with text-only contentParts does not add follow-up', () {
      const mapper = OpenAiMessageMapper();
      final msgs = [
        Message.user('hi'),
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'bash', arguments: {}),
        ]),
        Message.toolResult(
          callId: 'tc1',
          content: 'output',
          toolName: 'bash',
          contentParts: [const TextPart('output')],
        ),
      ];
      final result = mapper.mapMessages(msgs, systemPrompt: 'sys');
      // system + user + assistant + tool = 4 (no follow-up)
      expect(result.messages.length, 4);
    });
  });
}
