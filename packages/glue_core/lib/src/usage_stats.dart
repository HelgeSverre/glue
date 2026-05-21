/// Cumulative token-usage accounting shared by the agent loop, subagent
/// runner, title generator, and session persistence.
///
/// **Status:** part of the proposed core data model — see
/// `docs/plans/2026-04-29-harness-layers.md`.
///
/// `UsageStats` is mutable and meant to be aggregated across many LLM
/// calls within a session (or a subagent's lifetime). [record] folds a
/// single `UsageInfo` into the running totals. [merge] folds another
/// `UsageStats` (e.g. a finished subagent) into the parent's totals.
///
/// Use [snapshot] when you need to hand the current values to a sink that
/// shouldn't observe later mutations.
library;

import 'package:glue_core/src/message.dart';

class UsageStats {
  int inputTokens;
  int outputTokens;
  int cacheReadTokens;
  int cacheCreationTokens;
  int turnCount;

  UsageStats({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.turnCount = 0,
  });

  /// Folds a single [UsageInfo] chunk into the running totals. Increments
  /// [turnCount] every call regardless of whether the provider reported
  /// cache stats — `turnCount` measures LLM calls, not cache events.
  void record(UsageInfo usage) {
    inputTokens += usage.inputTokens;
    outputTokens += usage.outputTokens;
    cacheReadTokens += usage.cacheReadTokens ?? 0;
    cacheCreationTokens += usage.cacheCreationTokens ?? 0;
    turnCount++;
  }

  /// Folds another [UsageStats] into this one. Used to roll subagent
  /// totals into a parent's accumulator.
  void merge(UsageStats other) {
    inputTokens += other.inputTokens;
    outputTokens += other.outputTokens;
    cacheReadTokens += other.cacheReadTokens;
    cacheCreationTokens += other.cacheCreationTokens;
    turnCount += other.turnCount;
  }

  /// Sum of every counted token, billable or otherwise. Useful for the
  /// status-bar style "tokens used" indicator that doesn't need to
  /// distinguish cache reads from prompt tokens.
  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens;

  /// Total input the model "saw" — uncached input plus cache reads. The
  /// denominator for hit-rate calculations.
  int get billedInputTokens => inputTokens + cacheReadTokens;

  /// Cache hit rate as a fraction of total input the model saw, or `null`
  /// when no LLM call has been recorded yet (avoids a misleading 0%).
  double? get cacheHitRate =>
      billedInputTokens > 0 ? cacheReadTokens / billedInputTokens : null;

  /// Returns an immutable copy of the current totals. Use this when
  /// handing values to a sink that must not see later mutations.
  UsageStats snapshot() => UsageStats(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadTokens: cacheReadTokens,
    cacheCreationTokens: cacheCreationTokens,
    turnCount: turnCount,
  );

  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    if (cacheReadTokens > 0) 'cache_read_tokens': cacheReadTokens,
    if (cacheCreationTokens > 0) 'cache_creation_tokens': cacheCreationTokens,
    'turn_count': turnCount,
  };

  static UsageStats fromJson(Map<String, dynamic> json) => UsageStats(
    inputTokens: (json['input_tokens'] as int?) ?? 0,
    outputTokens: (json['output_tokens'] as int?) ?? 0,
    cacheReadTokens: (json['cache_read_tokens'] as int?) ?? 0,
    cacheCreationTokens: (json['cache_creation_tokens'] as int?) ?? 0,
    turnCount: (json['turn_count'] as int?) ?? 0,
  );

  @override
  String toString() =>
      'UsageStats(in: $inputTokens, out: $outputTokens, cacheRead: '
      '$cacheReadTokens, cacheWrite: $cacheCreationTokens, '
      'turns: $turnCount)';
}
