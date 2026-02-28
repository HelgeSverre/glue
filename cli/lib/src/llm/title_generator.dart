import 'dart:convert';
import 'package:http/http.dart' as http;

/// Generates short session titles using a lightweight LLM call.
class TitleGenerator {
  static const _apiVersion = '2023-06-01';
  static const _baseUrl = 'https://api.anthropic.com';
  static const _maxTitleLength = 60;

  static final _nonAsciiRe = RegExp(r'[^\x20-\x7E]');
  static final _whitespaceRe = RegExp(r'\s+');

  static const _systemPrompt =
      'Generate a short title (max 7 words, Sentence case) for this coding '
      'session. Respond with ONLY the title, nothing else. Do not assume '
      'intent beyond what is stated. Omit words like "question" or "request". '
      'Use software engineering terms when helpful.';

  final http.Client _http;
  final String _apiKey;
  final String _model;

  TitleGenerator({
    required http.Client httpClient,
    required String apiKey,
    required String model,
  })  : _http = httpClient,
        _apiKey = apiKey,
        _model = model;

  /// Generate a title from the first user message.
  ///
  /// Returns `null` if the API call fails for any reason.
  Future<String?> generate(String userMessage) async {
    try {
      final response = await _http.post(
        Uri.parse('$_baseUrl/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': _apiVersion,
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 30,
          'temperature': 0.7,
          'system': _systemPrompt,
          'messages': [
            {
              'role': 'user',
              'content': '<message>${_truncate(userMessage, 500)}</message>',
            },
          ],
        }),
      );

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final content = json['content'] as List<dynamic>?;
      if (content == null || content.isEmpty) return null;

      final text = (content[0] as Map<String, dynamic>)['text'] as String?;
      return sanitize(text);
    } catch (_) {
      return null;
    }
  }

  /// Sanitize a title to printable ASCII, collapsing whitespace.
  ///
  /// Returns `null` if the result is empty after sanitization.
  static String? sanitize(String? raw) {
    if (raw == null) return null;

    // Keep only printable ASCII (space through tilde).
    final cleaned =
        raw.replaceAll(_nonAsciiRe, '').replaceAll(_whitespaceRe, ' ').trim();

    if (cleaned.isEmpty) return null;

    return cleaned.length > _maxTitleLength
        ? cleaned.substring(0, _maxTitleLength).trim()
        : cleaned;
  }

  static String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';
}
