import 'dart:math';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/web/fetch/truncation.dart';

/// Tier 1: Replace large tool results from old turns with truncated placeholders.
///
/// Tool results (file reads, web fetches) are the biggest context consumers
/// and are rarely useful after a few turns. This trimmer replaces the content
/// of old tool results with a compact summary marker while preserving the
/// tool call metadata (name and ID).
///
/// No LLM call is required.
///
/// {@category Context}
class ToolResultTrimmer {
  /// Number of most-recent user turns whose tool results are kept intact.
  final int keepRecentN;

  const ToolResultTrimmer({this.keepRecentN = 3});

  /// Trim tool results from turns older than [keepRecentN] user turns.
  ///
  /// Results that are already short (≤ 200 estimated tokens) are kept as-is.
  List<Message> trim(List<Message> messages, {int? keepRecentN}) {
    final effectiveKeep = keepRecentN ?? this.keepRecentN;
    final userTurnBoundaries = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].role == Role.user) userTurnBoundaries.add(i);
    }

    if (userTurnBoundaries.length <= effectiveKeep) return messages;

    final recentCutoff =
        userTurnBoundaries[userTurnBoundaries.length - effectiveKeep];

    final result = <Message>[];
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (i < recentCutoff && msg.role == Role.toolResult) {
        final text = msg.text ?? '';
        final estimatedTokens = TokenTruncation.estimateTokens(text);
        if (estimatedTokens > 200) {
          // Keep a short preview so the model knows what happened.
          final previewChars = min(200 * 4, text.length);
          final preview = text.substring(0, previewChars);
          result.add(Message.toolResult(
            callId: msg.toolCallId!,
            content:
                '[tool result truncated — ~$estimatedTokens tokens]\n$preview...',
            toolName: msg.toolName,
          ));
          continue;
        }
      }
      result.add(msg);
    }
    return result;
  }
}
