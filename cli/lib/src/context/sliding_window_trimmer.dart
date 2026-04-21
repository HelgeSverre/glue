import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/context/context_estimator.dart';

/// Tier 3: Emergency sliding-window trim.
///
/// Drops the oldest complete turns (user → assistant → tool results) from the
/// conversation until the estimated token count fits within [targetTokens].
///
/// Always preserves at least [minimumRecentTurns] user turns so the model
/// has some recent context. A marker message is prepended when turns are
/// dropped.
///
/// No LLM call is required.
///
/// {@category Context}
class SlidingWindowTrimmer {
  final ContextEstimator estimator;

  SlidingWindowTrimmer({required this.estimator});

  /// Trim [messages] until estimated tokens fit within [targetTokens].
  List<Message> trim(
    List<Message> messages, {
    required int targetTokens,
    String systemPrompt = '',
    int minimumRecentTurns = 2,
  }) {
    var current = List<Message>.from(messages);

    while (estimator.estimate(current, systemPrompt: systemPrompt) >
            targetTokens &&
        _countUserTurns(current) > minimumRecentTurns) {
      current = _dropFirstTurn(current);
    }

    if (current.length < messages.length) {
      final dropped = messages.length - current.length;
      current.insert(
        0,
        Message.user(
          '[Earlier conversation was trimmed to fit context window. '
          '$dropped messages removed.]',
        ),
      );
    }

    return current;
  }

  int _countUserTurns(List<Message> messages) =>
      messages.where((m) => m.role == Role.user).length;

  /// Remove the first complete turn: the first user message and everything up
  /// to (but not including) the next user message.
  List<Message> _dropFirstTurn(List<Message> messages) {
    if (messages.isEmpty) return messages;

    int start = -1;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].role == Role.user) {
        start = i;
        break;
      }
    }
    if (start < 0) return messages;

    int end = messages.length;
    for (var i = start + 1; i < messages.length; i++) {
      if (messages[i].role == Role.user) {
        end = i;
        break;
      }
    }

    return messages.sublist(0, start)..addAll(messages.sublist(end));
  }
}
