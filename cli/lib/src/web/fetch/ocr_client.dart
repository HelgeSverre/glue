import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/utils.dart';

/// Client for OCR-based PDF text extraction using LLM vision APIs.
///
/// Supports Mistral OCR Small (pixtral-based) and OpenAI vision models.
/// Used as a fallback when pdftotext returns empty text (scanned PDFs).
class OcrClient {
  final OcrProviderType provider;
  final String apiKey;
  final String model;
  final int timeoutSeconds;
  final http.Client _client;

  OcrClient({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.timeoutSeconds = 120,
    http.Client? client,
  }) : _client = client ?? http.Client();

  factory OcrClient.fromConfig(PdfConfig config, {http.Client? client}) =>
      OcrClient(
        provider: config.ocrProvider,
        apiKey: config.ocrProvider == OcrProviderType.mistral
            ? config.mistralApiKey ?? ''
            : config.openaiApiKey ?? '',
        model: config.ocrProvider == OcrProviderType.mistral
            ? config.mistralModel
            : config.openaiModel,
        client: client,
      );

  Map<String, String> get headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// Extract text from PDF bytes via OCR API.
  Future<String?> extractText(Uint8List pdfBytes) async {
    try {
      return switch (provider) {
        OcrProviderType.mistral => await _extractViaMistral(pdfBytes),
        OcrProviderType.openai => await _extractViaOpenAI(pdfBytes),
      };
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _extractViaMistral(Uint8List pdfBytes) async {
    final uri = Uri.parse('https://api.mistral.ai/v1/ocr');
    final body = buildMistralRequestBody(pdfBytes);

    final response = await _client
        .post(uri, headers: headers, body: body)
        .timeout(timeoutSeconds.seconds);

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final pages = json['pages'] as List<dynamic>?;
    if (pages == null || pages.isEmpty) return null;

    final buf = StringBuffer();
    for (final page in pages) {
      final pageMap = page as Map<String, dynamic>;
      final markdown = pageMap['markdown'] as String? ?? '';
      if (markdown.isNotEmpty) {
        buf.writeln(markdown);
        buf.writeln();
      }
    }
    return buf.toString().trim().isEmpty ? null : buf.toString();
  }

  /// The OpenAI API endpoint for OCR requests.
  ///
  /// Uses the Responses API which natively supports PDF file inputs,
  /// unlike the Chat Completions API which only accepts images.
  String get openaiEndpoint => 'https://api.openai.com/v1/responses';

  Future<String?> _extractViaOpenAI(Uint8List pdfBytes) async {
    final uri = Uri.parse(openaiEndpoint);
    final body = buildOpenAIRequestBody(pdfBytes);

    final response = await _client
        .post(uri, headers: headers, body: body)
        .timeout(timeoutSeconds.seconds);

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final output = json['output'] as List<dynamic>?;
    if (output == null || output.isEmpty) return null;

    for (final item in output) {
      final itemMap = item as Map<String, dynamic>;
      if (itemMap['type'] == 'message') {
        final content = itemMap['content'] as List<dynamic>?;
        if (content == null) continue;
        for (final part in content) {
          final partMap = part as Map<String, dynamic>;
          if (partMap['type'] == 'output_text') {
            return partMap['text'] as String?;
          }
        }
      }
    }
    return null;
  }

  String buildMistralRequestBody(Uint8List pdfBytes) {
    final base64Pdf = base64Encode(pdfBytes);
    return jsonEncode({
      'model': model,
      'document': {
        'type': 'document_url',
        'document_url': 'data:application/pdf;base64,$base64Pdf',
      },
    });
  }

  String buildOpenAIRequestBody(Uint8List pdfBytes) {
    final base64Pdf = base64Encode(pdfBytes);
    return jsonEncode({
      'model': model,
      'input': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': 'Extract all text from this PDF document. '
                  'Return the text content as clean markdown, '
                  'preserving headings, lists, and structure.',
            },
            {
              'type': 'input_file',
              'filename': 'document.pdf',
              'file_data': 'data:application/pdf;base64,$base64Pdf',
            },
          ],
        },
      ],
    });
  }
}
