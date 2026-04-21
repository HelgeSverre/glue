/// Configuration for context window management.
///
/// {@category Context}
class ContextConfig {
  /// Whether automatic compaction is enabled.
  final bool autoCompact;

  /// Fraction of the input budget at which Tier 2 (summarization) fires.
  final double compactThreshold;

  /// Fraction of the input budget at which Tier 3 (sliding-window trim) fires.
  final double criticalThreshold;

  /// Number of recent user turns to always keep verbatim (Tier 2 + 3).
  final int keepRecentTurns;

  /// Trim tool results from turns older than this many user turns (Tier 1).
  final int toolResultTrimAfter;

  const ContextConfig({
    this.autoCompact = true,
    this.compactThreshold = 0.80,
    this.criticalThreshold = 0.95,
    this.keepRecentTurns = 4,
    this.toolResultTrimAfter = 3,
  });
}
