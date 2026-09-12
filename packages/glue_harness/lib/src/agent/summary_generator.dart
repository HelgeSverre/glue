import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/session/session_manager.dart';

/// Shared machinery for the small-model one-liner generators.
///
/// [TitleGenerator] names a session; [RecapGenerator] says what has happened
/// in it so far. They differ only in system prompt and length ceiling — the
/// context blob, streaming, sanitization and error handling live here.
abstract class SummaryGenerator {
  /// Ceiling on the sanitized output, ellipsis included.
  final int maxLength;

  /// Per-field cap on the context blob interpolated into the user message.
  final int fieldLimit;

  /// Deadline for the whole generation. These are background niceties — a
  /// hung provider stream must not leave a session titleless forever.
  static const timeout = Duration(seconds: 20);

  final LlmClient _llm;

  /// Optional per-call usage callback. Surfaces wire this to
  /// `SessionManager.recordUsage(stats, role: 'title' | 'recap')` so the
  /// small-model cost is accounted for in session totals.
  void Function(UsageInfo)? onUsage;

  SummaryGenerator({
    required LlmClient llmClient,
    required this.maxLength,
    required this.fieldLimit,
    this.onUsage,
  }) : _llm = llmClient;

  /// Generate from the compact tagged view of the conversation.
  ///
  /// Returns `null` if generation fails for any reason.
  Future<String?> generateFromContext(TitleContext context) =>
      _generate(_renderContext(context));

  String _renderContext(TitleContext context) {
    final buffer = StringBuffer();
    void tag(String name, String? value) {
      if (value == null || value.isEmpty) return;
      buffer.writeln('<$name>${_truncate(value, fieldLimit)}</$name>');
    }

    tag('cwd', context.cwdBasename);
    tag('first_user', context.firstUserMessage);
    tag('latest_user', context.latestUserMessage);
    tag('first_assistant', context.firstAssistantMessage);
    tag('latest_assistant', context.latestAssistantMessage);
    tag('tools', context.toolNames.join(', '));
    tag('files', context.filesTouched.join(', '));
    return buffer.toString().trim();
  }

  Future<String?> _generate(String userMessage) async {
    try {
      final response = StringBuffer();
      await _llm
          .stream([Message.user(userMessage)])
          .forEach((chunk) {
            switch (chunk) {
              case TextDelta(:final text):
                response.write(text);
              case UsageInfo():
                onUsage?.call(chunk);
              default:
                break;
            }
          })
          .timeout(timeout);
      return sanitizeTo(response.toString(), maxLength);
    } catch (_) {
      return null;
    }
  }

  // Control chars, combining marks (zalgo), and Other_Symbol (emoji,
  // dingbats). Deliberately *not* "everything outside ASCII" — that used to
  // destroy any non-English title and any accented identifier.
  static final _junkRe = RegExp(r'[\p{C}\p{M}\p{So}]', unicode: true);
  static final _whitespaceRe = RegExp(r'\s+');

  /// Clean a model response into a single printable line of at most
  /// [maxLength] characters, ellipsis included.
  ///
  /// Collapses whitespace, drops control/combining/emoji codepoints, strips
  /// the quotes models like to wrap one-line answers in, and cuts on a word
  /// boundary when it has to cut. Returns `null` if nothing survives.
  static String? sanitizeTo(String? raw, int maxLength) {
    if (raw == null) return null;

    // Collapse first, then strip: otherwise a newline is deleted outright and
    // the words on either side of it are glued together.
    var cleaned = raw
        .replaceAll(_whitespaceRe, ' ')
        .replaceAll(_junkRe, '')
        .trim();

    while (cleaned.length > 1 &&
        (cleaned.startsWith('"') && cleaned.endsWith('"') ||
            cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    if (cleaned.isEmpty) return null;
    if (cleaned.length <= maxLength) return cleaned;

    final cut = cleaned.substring(0, maxLength - 3);
    final lastSpace = cut.lastIndexOf(' ');
    final head = lastSpace > maxLength ~/ 2 ? cut.substring(0, lastSpace) : cut;
    return '${head.trimRight()}...';
  }

  /// Cap an interpolated value and neutralize the tag delimiters, so a user
  /// message (or a file quoted in one) cannot close a tag early or open its
  /// own and steer the model.
  static String _truncate(String s, int maxLen) {
    final capped = s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';
    return capped.replaceAll('<', '(').replaceAll('>', ')');
  }
}

/// Generates short session titles using an [LlmClient].
class TitleGenerator extends SummaryGenerator {
  static const _maxTitleLength = 60;

  static const systemPrompt = '''
You name coding sessions.

Write a title for the session described by the tagged fields in the user
message. Prefer the concrete task that emerged. Do not assume intent beyond
what the fields state.

Output the title alone, on one line: no quotes, no trailing period, no
preamble. Sentence case, at most 7 words and at most 60 characters. Omit
generic words like "question", "request", or "help". Use software engineering
terms where they fit.

Examples:

<first_user>the login is broken</first_user>
<tools>read_file, edit_file</tools>
Fix broken login flow

<first_user>help debug this</first_user>
<latest_user>it only fails in docker</latest_user>
<files>test/resume_test.dart</files>
Docker-only resume test flake

<first_user>can you look at why the build is slow</first_user>
Investigate slow build times''';

  TitleGenerator({required super.llmClient, super.onUsage})
    : super(maxLength: _maxTitleLength, fieldLimit: 300);

  /// Generate a title from the first user message, before any reply exists.
  Future<String?> generate(String userMessage) => _generate(
    '<message>${SummaryGenerator._truncate(userMessage, 500)}'
    '</message>',
  );

  /// Sanitize a title to a single printable line of at most 60 characters.
  static String? sanitize(String? raw) =>
      SummaryGenerator.sanitizeTo(raw, _maxTitleLength);
}

/// Generates a one-line session recap using a small [LlmClient].
///
/// Companion to [TitleGenerator]: titles describe what a session is about,
/// recaps describe what has happened in it so far.
class RecapGenerator extends SummaryGenerator {
  static const _maxRecapLength = 200;

  static const systemPrompt = '''
You summarize coding sessions that are still in progress.

Write one sentence describing what has happened so far in the session
described by the tagged fields in the user message. Report only what those
fields support: if an outcome is not stated, say what was worked on, not what
was achieved.

Output the sentence alone, on one line: plain prose, no bullets, no quotes, no
preamble. At most 25 words.

Examples:

<first_user>help debug this</first_user>
<latest_user>it only fails in docker</latest_user>
<tools>read_file, edit_file</tools>
<files>lib/src/shell/docker_executor.dart</files>
Traced a Docker-only resume failure and edited the Docker executor.

<first_user>can you look at why the build is slow</first_user>
<tools>run_shell_command</tools>
Started investigating slow build times by running the build.''';

  RecapGenerator({required super.llmClient, super.onUsage})
    : super(maxLength: _maxRecapLength, fieldLimit: 400);

  /// Sanitize a recap to a single printable line of at most 200 characters.
  static String? sanitize(String? raw) =>
      SummaryGenerator.sanitizeTo(raw, _maxRecapLength);
}
