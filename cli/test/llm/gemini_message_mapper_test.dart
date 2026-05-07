import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiMessageMapper', () {
    const mapper = GeminiMessageMapper();

    test('keeps system prompt separate (not a message)', () {
      final result = mapper.mapMessages(
        [Message.user('hello')],
        systemPrompt: 'You are Glue.',
      );
      expect(result.systemPrompt, 'You are Glue.');
      // Only the user message — no system role in the array.
      expect(result.messages, hasLength(1));
      expect(result.messages.first['role'], 'user');
    });

    test('maps user text into role: user / parts: [{text}]', () {
      final result = mapper.mapMessages(
        [Message.user('hi there')],
        systemPrompt: '',
      );
      expect(result.messages.first, {
        'role': 'user',
        'parts': [
          {'text': 'hi there'}
        ],
      });
    });

    test('maps assistant tool call as role: model / functionCall part', () {
      final result = mapper.mapMessages(
        [
          Message.user('read foo'),
          Message.assistant(text: 'ok', toolCalls: [
            ToolCall(
                id: const ToolCallId('tc1'),
                name: 'read_file',
                arguments: {'path': 'f.txt'}),
          ]),
        ],
        systemPrompt: '',
      );

      final assistant = result.messages[1];
      expect(assistant['role'], 'model');
      final parts = assistant['parts'] as List;
      expect(parts, hasLength(2));
      expect(parts.first, {'text': 'ok'});
      expect(parts[1], {
        'functionCall': {
          'name': 'read_file',
          'args': {'path': 'f.txt'},
        },
      });
    });

    test('echoes thoughtSignature on the functionCall part when present', () {
      final result = mapper.mapMessages(
        [
          Message.user('q'),
          Message.assistant(toolCalls: [
            ToolCall(
              id: const ToolCallId('tc1'),
              name: 'web_search',
              arguments: {'query': 'q'},
              thoughtSignature: 'sig-from-prev-turn',
            ),
          ]),
        ],
        systemPrompt: '',
      );

      final assistant = result.messages[1];
      final parts = assistant['parts'] as List;
      expect(parts, hasLength(1));
      expect(parts.first, {
        'functionCall': {
          'name': 'web_search',
          'args': {'query': 'q'},
        },
        'thoughtSignature': 'sig-from-prev-turn',
      });
    });

    test('omits thoughtSignature key when ToolCall does not carry one', () {
      final result = mapper.mapMessages(
        [
          Message.user('q'),
          Message.assistant(toolCalls: [
            ToolCall(
                id: const ToolCallId('tc1'),
                name: 'read_file',
                arguments: {'path': 'x'}),
          ]),
        ],
        systemPrompt: '',
      );

      final assistant = result.messages[1];
      final parts = assistant['parts'] as List;
      final part = parts.first as Map<String, dynamic>;
      expect(part.containsKey('thoughtSignature'), isFalse);
    });

    test('maps tool result as role: user / functionResponse part', () {
      final result = mapper.mapMessages(
        [
          Message.user('read foo'),
          Message.assistant(toolCalls: [
            ToolCall(
                id: const ToolCallId('tc1'),
                name: 'read_file',
                arguments: {'path': 'f.txt'}),
          ]),
          Message.toolResult(
            callId: const ToolCallId('tc1'),
            toolName: 'read_file',
            content: 'file contents',
          ),
        ],
        systemPrompt: '',
      );

      final last = result.messages.last;
      expect(last['role'], 'user');
      final parts = last['parts'] as List;
      expect(parts.first, {
        'functionResponse': {
          'name': 'read_file',
          'response': {'content': 'file contents'},
        },
      });
    });

    test('drops orphaned tool_result whose toolName has no prior call', () {
      final result = mapper.mapMessages(
        [
          Message.user('hello'),
          Message.toolResult(
            callId: const ToolCallId('tc1'),
            toolName: 'read_file',
            content: 'orphan',
          ),
        ],
        systemPrompt: '',
      );

      // The orphan must NOT appear; only the user message remains.
      expect(result.messages, hasLength(1));
      expect(result.messages.first['role'], 'user');
    });

    test('coalesces consecutive same-role messages', () {
      final result = mapper.mapMessages(
        [
          Message.user('one'),
          Message.user('two'),
        ],
        systemPrompt: '',
      );

      // Two user messages collapse into a single role:user with both parts.
      expect(result.messages, hasLength(1));
      final parts = result.messages.first['parts'] as List;
      expect(parts, [
        {'text': 'one'},
        {'text': 'two'},
      ]);
    });

    test('image parts in tool result emit inlineData parts', () {
      final result = mapper.mapMessages(
        [
          Message.assistant(toolCalls: [
            ToolCall(
                id: const ToolCallId('tc1'), name: 'screenshot', arguments: {}),
          ]),
          Message.toolResult(
            callId: const ToolCallId('tc1'),
            toolName: 'screenshot',
            content: '',
            contentParts: [
              const TextPart('see image'),
              const ImagePart(bytes: [1, 2, 3], mimeType: 'image/png'),
            ],
          ),
        ],
        systemPrompt: '',
      );

      final last = result.messages.last;
      final parts = last['parts'] as List;
      // functionResponse first, then the inlineData image.
      expect((parts.first as Map)['functionResponse'], isNotNull);
      expect(parts.last, {
        'inlineData': {
          'mimeType': 'image/png',
          'data': 'AQID',
        },
      });
    });
  });
}
