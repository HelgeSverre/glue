import 'package:glue/src/agent/agent_core.dart';

/// Tier 2: Summarize older conversation turns using a small LLM call.
///
/// When estimated token usage exceeds the compaction threshold, older turns
/// are replaced by a condensed summary produced by [summaryClient]. The most
/// recent [keepRecentTurns] user turns are always kept verbatim.
///
/// The summary is injected as a synthetic user message so downstream
/// processing can handle it without special-casing.
///
/// {@category Context}
class ConversationCompactor {
  final LlmClient _summaryClient;

  /// Number of most-recent user turns to keep verbatim.
  final int keepRecentTurns;

  const ConversationCompactor({
    required LlmClient summaryClient,
    this.keepRecentTurns = 4,
  }) : _summaryClient = summaryClient;

  /// Compact the conversation by summarizing all but the last
  /// [keepRecentTurns] user turns.
  ///
  /// Returns [conversation] unchanged when it is already short enough.
  Future<List<Message>> compact(List<Message> conversation) async {
    final turnBoundaries = _findUserTurnBoundaries(conversation);
    if (turnBoundaries.length <= keepRecentTurns + 1) return conversation;

    final compactUpTo = turnBoundaries[turnBoundaries.length - keepRecentTurns];
    final oldMessages = conversation.sublist(0, compactUpTo);
    final recentMessages = conversation.sublist(compactUpTo);

    final summary = await _summarize(oldMessages);

    return [
      Message.user(
          '[Session context summary — earlier conversation]\n$summary'),
      ...recentMessages,
    ];
  }

  Future<String> _summarize(List<Message> messages) async {
    final prompt = _buildSummaryPrompt(messages);
    final chunks = <String>[];
    await for (final chunk in _summaryClient.stream([Message.user(prompt)])) {
      if (chunk case TextDelta(:final text)) chunks.add(text);
    }
    return chunks.join();
  }

  String _buildSummaryPrompt(List<Message> messages) {
    final buf = StringBuffer(
      'Summarize the following conversation for a coding AI assistant. '
      'Focus on: goals accomplished, files modified, key decisions made, '
      'errors encountered. Be concise but preserve technical details.\n\n',
    );
    for (final msg in messages) {
      switch (msg.role) {
        case Role.user:
          buf.write('USER: ${msg.text ?? ''}\n\n');
        case Role.assistant:
          if (msg.text?.isNotEmpty == true) {
            buf.write('ASSISTANT: ${msg.text}\n\n');
          }
          if (msg.toolCalls.isNotEmpty) {
            for (final tc in msg.toolCalls) {
              buf.write('TOOL CALL: ${tc.name}\n\n');
            }
          }
        case Role.toolResult:
          final text = msg.text ?? '';
          final preview =
              text.length > 500 ? '${text.substring(0, 500)}...' : text;
          buf.write('TOOL RESULT (${msg.toolName ?? 'unknown'}): $preview\n\n');
      }
    }
    return buf.toString();
  }

  List<int> _findUserTurnBoundaries(List<Message> messages) {
    final boundaries = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].role == Role.user) boundaries.add(i);
    }
    return boundaries;
  }
}
