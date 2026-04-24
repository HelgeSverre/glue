import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/session/session_manager.dart';

/// Generates short session titles using an [LlmClient].
class TitleGenerator {
  static const _maxTitleLength = 60;

  static final _nonAsciiRe = RegExp(r'[^\x20-\x7E]');
  static final _whitespaceRe = RegExp(r'\s+');

  static const systemPrompt =
      'Generate a short title (max 7 words, Sentence case) for this coding '
      'session. Prefer the concrete task that emerged from the conversation. '
      'Respond with ONLY the title, nothing else. Do not assume intent beyond '
      'what is stated. Omit generic words like "question", "request", or '
      '"help". Use software engineering terms when helpful.';

  TitleGenerator({
    required LlmClient llmClient,
  }) : _llm = llmClient;

  final LlmClient _llm;

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

  Future<String?> generateFromContext(TitleContext context) async {
    try {
      final buffer = StringBuffer();
      if (context.cwdBasename case final cwd? when cwd.isNotEmpty) {
        buffer.writeln('<cwd>$cwd</cwd>');
      }
      if (context.firstUserMessage case final text? when text.isNotEmpty) {
        buffer.writeln('<first_user>${_truncate(text, 300)}</first_user>');
      }
      if (context.latestUserMessage case final text? when text.isNotEmpty) {
        buffer.writeln('<latest_user>${_truncate(text, 300)}</latest_user>');
      }
      if (context.firstAssistantMessage case final text? when text.isNotEmpty) {
        buffer.writeln(
            '<first_assistant>${_truncate(text, 300)}</first_assistant>');
      }
      if (context.latestAssistantMessage case final text?
          when text.isNotEmpty) {
        buffer.writeln(
            '<latest_assistant>${_truncate(text, 300)}</latest_assistant>');
      }
      if (context.toolNames.isNotEmpty) {
        buffer.writeln('<tools>${context.toolNames.join(', ')}</tools>');
      }

      final stream = _llm.stream([Message.user(buffer.toString().trim())]);
      final response = StringBuffer();
      await for (final chunk in stream) {
        if (chunk case TextDelta(:final text)) {
          response.write(text);
        }
      }
      return sanitize(response.toString());
    } catch (_) {
      return null;
    }
  }

  /// Sanitize a title to printable ASCII, collapsing whitespace.
  ///
  /// Returns `null` if the result is empty after sanitization.
  static String? sanitize(String? raw) {
    if (raw == null) return null;

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
