import 'package:glue/src/agent/agent_core.dart';

/// Generates short session titles using an [LlmClient].
class TitleGenerator {
  static const _maxTitleLength = 60;

  static final _nonAsciiRe = RegExp(r'[^\x20-\x7E]');
  static final _whitespaceRe = RegExp(r'\s+');

  static const systemPrompt =
      'Generate a short title (max 7 words, Sentence case) for this coding '
      'session. Respond with ONLY the title, nothing else. Do not assume '
      'intent beyond what is stated. Omit words like "question" or "request". '
      'Use software engineering terms when helpful.';

  final LlmClient _llm;

  TitleGenerator({
    required LlmClient llmClient,
  }) : _llm = llmClient;

  /// Generate a title from the first user message.
  ///
  /// Returns `null` if title generation fails for any reason.
  Future<String?> generate(String userMessage) async {
    try {
      final stream = _llm.stream([
        Message.user('<message>${_truncate(userMessage, 500)}</message>'),
      ]);

      final buffer = StringBuffer();
      await for (final chunk in stream) {
        if (chunk case TextDelta(:final text)) {
          buffer.write(text);
        }
      }

      return sanitize(buffer.toString());
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
