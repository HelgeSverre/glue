import 'dart:convert';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/web/fetch/truncation.dart';

/// Estimates token counts for conversations using a character-based heuristic.
///
/// The baseline ratio of ~4 characters per token is calibrated against actual
/// provider-reported [UsageInfo.inputTokens] after each turn via an
/// exponential moving average.
///
/// {@category Context}
class ContextEstimator {
  /// Current EMA calibration ratio (actual / raw-estimate).
  ///
  /// Starts at 1.0 (no correction). Updated by [calibrate] after each turn.
  double calibrationRatio = 1.0;

  /// Raw (pre-calibration) estimate for [messages] plus [systemPrompt].
  ///
  /// Counts tool-call argument JSON and name overhead in addition to message
  /// text. Does *not* apply [calibrationRatio].
  int estimateRaw(List<Message> messages, {String systemPrompt = ''}) {
    var total = TokenTruncation.estimateTokens(systemPrompt);
    for (final msg in messages) {
      total += TokenTruncation.estimateTokens(msg.text ?? '');
      for (final tc in msg.toolCalls) {
        total += TokenTruncation.estimateTokens(jsonEncode(tc.arguments));
        // Name + structural overhead per tool call.
        total += TokenTruncation.estimateTokens(tc.name) + 10;
      }
    }
    return total;
  }

  /// Calibrated estimate: [estimateRaw] × [calibrationRatio].
  int estimate(List<Message> messages, {String systemPrompt = ''}) {
    final raw = estimateRaw(messages, systemPrompt: systemPrompt);
    return (raw * calibrationRatio).round();
  }

  /// Update [calibrationRatio] from provider-reported token counts.
  ///
  /// [rawEstimate] is the value from [estimateRaw] (before calibration).
  /// [actual] is the provider's [UsageInfo.inputTokens].
  void calibrate(int rawEstimate, int actual) {
    if (rawEstimate > 0 && actual > 0) {
      final ratio = actual / rawEstimate;
      calibrationRatio = 0.7 * calibrationRatio + 0.3 * ratio;
    }
  }

  /// Reset [calibrationRatio] to 1.0 (e.g. after a model switch).
  void resetCalibration() => calibrationRatio = 1.0;
}
