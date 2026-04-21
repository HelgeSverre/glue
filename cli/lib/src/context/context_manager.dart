import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/context/context_budget.dart';
import 'package:glue/src/context/context_estimator.dart';
import 'package:glue/src/context/conversation_compactor.dart';
import 'package:glue/src/context/sliding_window_trimmer.dart';
import 'package:glue/src/context/tool_result_trimmer.dart';
import 'package:glue/src/observability/observability.dart';

/// Result of a forced compaction via [ContextManager.forceCompact].
///
/// {@category Context}
class CompactionResult {
  /// Estimated tokens freed by compaction.
  final int removedTokens;

  /// Estimated tokens used by the compaction summary.
  final int summaryTokens;

  const CompactionResult({
    required this.removedTokens,
    required this.summaryTokens,
  });
}

/// Orchestrates context-window management for the agent loop.
///
/// Sits between [AgentCore] and [LlmClient], preparing a token-budget-aware
/// view of the conversation before each LLM call. The original conversation
/// is never mutated — only the view sent to the LLM is affected.
///
/// Three tiers of reduction are applied in order of increasing aggressiveness:
/// 1. **Tool result trimming** — replaces large old tool results with placeholders.
///    No LLM call required.
/// 2. **Summarization compaction** — summarizes older turns with a small model.
///    Only runs when [compactor] is configured.
/// 3. **Sliding-window trim** — drops the oldest turns entirely.
///    No LLM call required.
///
/// {@category Context}
class ContextManager {
  final ContextBudget budget;
  final ContextEstimator estimator;
  final ToolResultTrimmer toolTrimmer;
  final ConversationCompactor? compactor;
  final SlidingWindowTrimmer slidingWindow;
  final Observability? _obs;

  /// Whether automatic compaction (Tier 2) is enabled.
  final bool autoCompact;

  /// System prompt used for token estimation.
  final String systemPrompt;

  /// Raw (pre-calibration) estimate from the most recent [prepareForLlm] call.
  int _lastRawEstimate = 0;
  int get lastRawEstimate => _lastRawEstimate;

  /// Pre-computed emergency-trimmed messages to use on the next LLM call.
  ///
  /// Set by [requestEmergencyTrim] when an overflow is detected; consumed
  /// and cleared by [prepareForLlm].
  List<Message>? _emergencyTrimmed;

  /// Pre-computed compacted messages to use on the next LLM call.
  ///
  /// Set by [forceCompact] (the `/compact` slash command); consumed and
  /// cleared by [prepareForLlm].
  List<Message>? _forcedCompaction;

  ContextManager({
    required this.budget,
    required this.estimator,
    required this.slidingWindow,
    ToolResultTrimmer? toolTrimmer,
    this.compactor,
    Observability? obs,
    this.autoCompact = true,
    this.systemPrompt = '',
  })  : toolTrimmer = toolTrimmer ?? const ToolResultTrimmer(),
        _obs = obs;

  /// Convenience factory that wires [estimator] and [slidingWindow] together.
  factory ContextManager.fromBudget(
    ContextBudget budget, {
    ConversationCompactor? compactor,
    Observability? obs,
    bool autoCompact = true,
    String systemPrompt = '',
  }) {
    final estimator = ContextEstimator();
    return ContextManager(
      budget: budget,
      estimator: estimator,
      slidingWindow: SlidingWindowTrimmer(estimator: estimator),
      compactor: compactor,
      obs: obs,
      autoCompact: autoCompact,
      systemPrompt: systemPrompt,
    );
  }

  /// Prepare a context-managed view of [conversation] for the next LLM call.
  ///
  /// Applies tiers in order: tool-result trim → compaction → sliding-window
  /// trim. Returns a new list; [conversation] is never mutated.
  Future<List<Message>> prepareForLlm(List<Message> conversation) async {
    // Emergency trim requested after an overflow — use once, then clear.
    if (_emergencyTrimmed != null) {
      final messages = _emergencyTrimmed!;
      _emergencyTrimmed = null;
      return messages;
    }

    // Forced compaction from `/compact` command — use once, then clear.
    if (_forcedCompaction != null) {
      final messages = _forcedCompaction!;
      _forcedCompaction = null;
      return messages;
    }

    var messages = List<Message>.from(conversation);

    // Track raw estimate for calibration.
    _lastRawEstimate = estimator.estimateRaw(
      messages,
      systemPrompt: systemPrompt,
    );
    final estimated = (estimator.calibrationRatio * _lastRawEstimate).round();

    // Tier 1: Always trim large old tool results.
    messages = toolTrimmer.trim(messages);

    // Tier 2: Summarize if above compaction threshold.
    if (autoCompact && estimated > budget.compactAt && compactor != null) {
      try {
        final originalEstimate = estimated;
        messages = await compactor!.compact(messages);
        final newEstimate =
            estimator.estimate(messages, systemPrompt: systemPrompt);
        _emitSpan('context.compact', {
          'context.original_tokens': originalEstimate,
          'context.compacted_tokens': newEstimate,
          'context.strategy': 'summarization',
        });
      } catch (_) {
        // Compaction failed — fall through to Tier 3.
      }
    }

    // Tier 3: Hard trim if still over critical threshold.
    final postEstimate =
        estimator.estimate(messages, systemPrompt: systemPrompt);
    if (postEstimate > budget.criticalAt) {
      final before = messages.length;
      messages = slidingWindow.trim(
        messages,
        // Trim back to 80 % (compactAt), not just past the 95 % threshold.
        targetTokens: budget.compactAt,
        systemPrompt: systemPrompt,
      );
      _emitSpan('context.sliding_window', {
        'context.dropped_messages': before - messages.length,
      });
    }

    return messages;
  }

  /// Request an emergency trim for the next [prepareForLlm] call.
  ///
  /// Called when an [ContextOverflowException] is detected during streaming.
  /// The next invocation of [prepareForLlm] will return aggressively trimmed
  /// messages (60 % of input budget) instead of running the normal tiers.
  void requestEmergencyTrim(List<Message> conversation) {
    _emergencyTrimmed = emergencyTrim(conversation);
  }

  /// Produce an aggressively trimmed message list (targeting 60 % of budget).
  ///
  /// Used for the one-shot overflow retry. No LLM call is made.
  List<Message> emergencyTrim(List<Message> messages) {
    final tier1 = toolTrimmer.trim(messages, keepRecentN: 2);
    return slidingWindow.trim(
      tier1,
      targetTokens: (budget.inputBudget * 0.6).round(),
      systemPrompt: systemPrompt,
    );
  }

  /// Force a compaction regardless of thresholds.
  ///
  /// Used by the `/compact` slash command. Computes and stores the compacted
  /// messages so the next [prepareForLlm] call uses them. Returns stats about
  /// the compaction.
  ///
  /// If no [compactor] is configured, applies Tier 1 + 3 trimming instead.
  Future<CompactionResult> forceCompact(List<Message> conversation) async {
    final originalEstimate =
        estimator.estimate(conversation, systemPrompt: systemPrompt);

    List<Message> compacted;
    if (compactor != null) {
      compacted = await compactor!.compact(conversation);
    } else {
      // Fallback: tool-result trim + sliding-window to compactAt.
      final tier1 = toolTrimmer.trim(conversation);
      compacted = slidingWindow.trim(
        tier1,
        targetTokens: budget.compactAt,
        systemPrompt: systemPrompt,
      );
    }

    final newEstimate =
        estimator.estimate(compacted, systemPrompt: systemPrompt);
    _forcedCompaction = compacted;

    return CompactionResult(
      removedTokens:
          originalEstimate > newEstimate ? originalEstimate - newEstimate : 0,
      summaryTokens: newEstimate,
    );
  }

  void _emitSpan(String name, Map<String, dynamic> attributes) {
    final obs = _obs;
    if (obs == null) return;
    final span = obs.startSpan(name, kind: 'internal', attributes: attributes);
    obs.endSpan(span);
  }
}
