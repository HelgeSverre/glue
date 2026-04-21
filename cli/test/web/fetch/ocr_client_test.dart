import 'dart:convert';
import 'dart:typed_data';

import 'package:glue/src/web/fetch/ocr_client.dart';
import 'package:glue/src/web/web_config.dart';
import 'package:test/test.dart';

void main() {
  group('OcrClient', () {
    test('creates Mistral request body correctly', () {
      final client = OcrClient(
        provider: OcrProviderType.mistral,
        apiKey: 'test-key',
        model: 'mistral-ocr-small',
      );
      final body = client.buildMistralRequestBody(
        Uint8List.fromList([1, 2, 3]),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['model'], 'mistral-ocr-small');
      expect(json['document'], isNotNull);
    });

    test('creates OpenAI request body with Responses API format', () {
      final client = OcrClient(
        provider: OcrProviderType.openai,
        apiKey: 'test-key',
        model: 'gpt-4.1-mini',
      );
      final body = client.buildOpenAIRequestBody(
        Uint8List.fromList([1, 2, 3]),
      );
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['model'], 'gpt-4.1-mini');

      // Must use Responses API 'input' field, not 'messages'.
      expect(json.containsKey('input'), isTrue,
          reason: 'Should use Responses API input field');
      expect(json.containsKey('messages'), isFalse,
          reason: 'Should not use Chat Completions messages field');

      final input = json['input'] as List;
      final userMsg = input[0] as Map<String, dynamic>;
      final content = userMsg['content'] as List;

      // Must use input_file type (not image_url or file).
      final fileContent = content[1] as Map<String, dynamic>;
      expect(fileContent['type'], 'input_file',
          reason: 'OpenAI Responses API uses input_file for PDFs');
    });

    test('OpenAI endpoint uses Responses API URL', () {
      final client = OcrClient(
        provider: OcrProviderType.openai,
        apiKey: 'test-key',
        model: 'gpt-4.1-mini',
      );
      expect(client.openaiEndpoint, 'https://api.openai.com/v1/responses');
    });

    test('headers include authorization', () {
      final client = OcrClient(
        provider: OcrProviderType.mistral,
        apiKey: 'test-key',
        model: 'mistral-ocr-small',
      );
      expect(client.headers['Authorization'], 'Bearer test-key');
    });
  });
}
