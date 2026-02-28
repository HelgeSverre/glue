import 'dart:convert';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/llm/ollama_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Mock HTTP client that captures the request body and returns a valid
/// Ollama NDJSON response so [OllamaClient.stream] completes normally.
class _CapturingClient extends http.BaseClient {
  Map<String, dynamic>? capturedBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
    }
    final ndjson = '${jsonEncode({
          'message': {'role': 'assistant', 'content': 'ok'},
          'done': true,
          'prompt_eval_count': 1,
          'eval_count': 1,
        })}\n';
    return http.StreamedResponse(
      Stream.value(utf8.encode(ndjson)),
      200,
    );
  }
}

void main() {
  group('OllamaClient message mapping', () {
    late _CapturingClient mockClient;
    late OllamaClient client;

    setUp(() {
      mockClient = _CapturingClient();
      client = OllamaClient(
        model: 'test',
        systemPrompt: '',
        requestClientFactory: () => mockClient,
      );
    });

    test(
        'tool_result with images adds follow-up user message with images array',
        () async {
      final messages = [
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

      await client.stream(messages).drain();

      expect(mockClient.capturedBody, isNotNull);
      final mappedMsgs = mockClient.capturedBody!['messages'] as List;
      // user + assistant + tool + follow-up user = 4
      expect(mappedMsgs.length, 4);
      // Tool result is text-only
      final toolMsg = mappedMsgs[2] as Map<String, dynamic>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['content'], 'Screenshot captured.');
      // Follow-up user has images
      final followUp = mappedMsgs[3] as Map<String, dynamic>;
      expect(followUp['role'], 'user');
      expect(followUp['images'], isList);
      final images = followUp['images'] as List;
      expect(images.length, 1);
      // Ollama wants raw base64 (no data URI prefix)
      expect(images[0], base64Encode([1, 2, 3]));
      expect(followUp['content'], contains('[Screenshot from web_browser]'));
    });

    test('tool_result without images has no follow-up message', () async {
      final messages = [
        Message.user('hi'),
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'bash', arguments: {}),
        ]),
        Message.toolResult(
          callId: 'tc1',
          content: 'output',
          toolName: 'bash',
        ),
      ];

      await client.stream(messages).drain();

      expect(mockClient.capturedBody, isNotNull);
      final mappedMsgs = mockClient.capturedBody!['messages'] as List;
      // user + assistant + tool = 3
      expect(mappedMsgs.length, 3);
      final toolMsg = mappedMsgs[2] as Map<String, dynamic>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['content'], 'output');
    });

    test('tool_result with contentParts but no images uses text only',
        () async {
      final messages = [
        Message.user('hi'),
        Message.assistant(toolCalls: [
          ToolCall(id: 'tc1', name: 'read_file', arguments: {}),
        ]),
        Message.toolResult(
          callId: 'tc1',
          content: 'fallback',
          toolName: 'read_file',
          contentParts: [
            const TextPart('file contents here'),
          ],
        ),
      ];

      await client.stream(messages).drain();

      expect(mockClient.capturedBody, isNotNull);
      final mappedMsgs = mockClient.capturedBody!['messages'] as List;
      // user + assistant + tool = 3 (no follow-up)
      expect(mappedMsgs.length, 3);
      final toolMsg = mappedMsgs[2] as Map<String, dynamic>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['content'], 'file contents here');
    });
  });
}
