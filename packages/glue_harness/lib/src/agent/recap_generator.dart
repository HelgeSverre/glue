import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/session/session_manager.dart';

/// Generates a one-line session recap using a small [LlmClient].
///
/// Companion to [TitleGenerator]: titles describe what a session is about,
/// recaps describe what has happened in it so far. Same shape, different
/// prompt and a slightly relaxed length ceiling.
class RecapGenerator {
  static const _maxRecapLength = 200;

  static final _nonAsciiRe = RegExp(r'[^\x20-\x7E]');
  static final _whitespaceRe = RegExp(r'\s+');

  static const systemPrompt =
      'Generate a single concise sentence (max 25 words) summarizing what '
      'has happened in this coding session so far. Focus on the concrete '
      'task and outcomes (e.g., "Investigated X, then refactored Y to use '
      'Z"). Plain prose, no bullets, no quotes. Respond with ONLY the '
      'sentence.';

  final LlmClient _llm;

  /// Optional per-call usage callback. Surfaces wire this to
  /// `SessionManager.recordUsage(stats, role: 'recap')` so recap cost is
  /// accounted for in session totals.
  void Function(UsageInfo)? onUsage;

  RecapGenerator({required LlmClient llmClient, this.onUsage})
    : _llm = llmClient;

  Future<String?> generateFromContext(TitleContext context) async {
    try {
      final buffer = StringBuffer();
      if (context.cwdBasename case final cwd? when cwd.isNotEmpty) {
        buffer.writeln('<cwd>$cwd</cwd>');
      }
      if (context.firstUserMessage case final text? when text.isNotEmpty) {
        buffer.writeln('<first_user>${_truncate(text, 400)}</first_user>');
      }
      if (context.latestUserMessage case final text? when text.isNotEmpty) {
        buffer.writeln('<latest_user>${_truncate(text, 400)}</latest_user>');
      }
      if (context.firstAssistantMessage case final text? when text.isNotEmpty) {
        buffer.writeln(
          '<first_assistant>${_truncate(text, 400)}</first_assistant>',
        );
      }
      if (context.latestAssistantMessage case final text?
          when text.isNotEmpty) {
        buffer.writeln(
          '<latest_assistant>${_truncate(text, 400)}</latest_assistant>',
        );
      }
      if (context.toolNames.isNotEmpty) {
        buffer.writeln('<tools>${context.toolNames.join(', ')}</tools>');
      }

      final stream = _llm.stream([Message.user(buffer.toString().trim())]);
      final response = StringBuffer();
      await for (final chunk in stream) {
        switch (chunk) {
          case TextDelta(:final text):
            response.write(text);
          case UsageInfo():
            onUsage?.call(chunk);
          default:
            break;
        }
      }
      return sanitize(response.toString());
    } catch (_) {
      return null;
    }
  }

  /// Sanitize a recap to printable ASCII, collapsing whitespace and
  /// stripping leading/trailing quotes the model occasionally adds.
  ///
  /// Returns `null` if the result is empty after sanitization.
  static String? sanitize(String? raw) {
    if (raw == null) return null;

    var cleaned = raw
        .replaceAll(_nonAsciiRe, '')
        .replaceAll(_whitespaceRe, ' ')
        .trim();

    while (cleaned.isNotEmpty &&
        (cleaned.startsWith('"') || cleaned.startsWith("'"))) {
      cleaned = cleaned.substring(1).trim();
    }
    while (cleaned.isNotEmpty &&
        (cleaned.endsWith('"') || cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }

    if (cleaned.isEmpty) return null;

    return cleaned.length > _maxRecapLength
        ? '${cleaned.substring(0, _maxRecapLength).trim()}...'
        : cleaned;
  }

  static String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';
}
