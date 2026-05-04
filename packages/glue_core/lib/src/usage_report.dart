/// Aggregator + data model for per-role token-usage breakdowns.
///
/// Reads persisted `usage` JSONL rows (written by
/// [SessionManager.recordUsage]) and folds them into a [UsageReport]
/// keyed by role. Used by the CLI's `/usage` slash command, the ACP
/// `session/usage_summary` endpoint, and session-resume headers.
library;

/// One row in the per-role breakdown table.
class UsageReportRow {
  final String role;
  final int calls;
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  const UsageReportRow({
    required this.role,
    required this.calls,
    required this.input,
    required this.output,
    required this.cacheRead,
    required this.cacheWrite,
  });

  int get totalTokens => input + output + cacheRead + cacheWrite;

  Map<String, dynamic> toJson() => {
        'role': role,
        'calls': calls,
        'input_tokens': input,
        'output_tokens': output,
        if (cacheRead > 0) 'cache_read_tokens': cacheRead,
        if (cacheWrite > 0) 'cache_creation_tokens': cacheWrite,
      };
}

/// Aggregated breakdown of a session's token usage.
class UsageReport {
  final String? modelLabel;
  final String? sessionId;
  final List<UsageReportRow> rows;

  const UsageReport({
    this.modelLabel,
    this.sessionId,
    required this.rows,
  });

  int get totalCalls => rows.fold(0, (sum, r) => sum + r.calls);
  int get totalInput => rows.fold(0, (sum, r) => sum + r.input);
  int get totalOutput => rows.fold(0, (sum, r) => sum + r.output);
  int get totalCacheRead => rows.fold(0, (sum, r) => sum + r.cacheRead);
  int get totalCacheWrite => rows.fold(0, (sum, r) => sum + r.cacheWrite);
  int get totalTokens =>
      totalInput + totalOutput + totalCacheRead + totalCacheWrite;

  /// Cache hit rate across **input** tokens that the model saw — uncached
  /// input plus cache reads. Returns null when no LLM call has been
  /// recorded (avoids a misleading 0%).
  double? get cacheHitRate {
    final billedInput = totalInput + totalCacheRead;
    return billedInput > 0 ? totalCacheRead / billedInput : null;
  }

  Map<String, dynamic> toJson() => {
        if (modelLabel != null) 'model': modelLabel,
        if (sessionId != null) 'session_id': sessionId,
        'totals': {
          'calls': totalCalls,
          'input_tokens': totalInput,
          'output_tokens': totalOutput,
          if (totalCacheRead > 0) 'cache_read_tokens': totalCacheRead,
          if (totalCacheWrite > 0) 'cache_creation_tokens': totalCacheWrite,
          'total_tokens': totalTokens,
          if (cacheHitRate != null) 'cache_hit_rate': cacheHitRate,
        },
        'by_role': [for (final r in rows) r.toJson()],
      };
}

/// Builds a [UsageReport] from persisted `usage` rows in
/// `conversation.jsonl`. Unknown roles are surfaced as their own row so
/// the report stays truthful even if a future surface adds new roles.
UsageReport buildUsageReport({
  required Iterable<Map<String, dynamic>> usageEvents,
  String? modelLabel,
  String? sessionId,
}) {
  final byRole = <String, _Acc>{};
  for (final e in usageEvents) {
    if (e['type'] != 'usage') continue;
    final role = (e['role'] as String?)?.trim() ?? 'unknown';
    final acc = byRole.putIfAbsent(role, _Acc.new);
    acc.calls += (e['turn_count'] as int?) ?? 1;
    acc.input += (e['input_tokens'] as int?) ?? 0;
    acc.output += (e['output_tokens'] as int?) ?? 0;
    acc.cacheRead += (e['cache_read_tokens'] as int?) ?? 0;
    acc.cacheWrite += (e['cache_creation_tokens'] as int?) ?? 0;
  }

  // Preferred display order; unknown roles fall through alphabetically.
  const knownOrder = ['main', 'subagent', 'title'];
  final ordered = <String>[
    ...knownOrder.where(byRole.containsKey),
    ...byRole.keys.where((r) => !knownOrder.contains(r)).toList()..sort(),
  ];

  return UsageReport(
    modelLabel: modelLabel,
    sessionId: sessionId,
    rows: [
      for (final role in ordered)
        UsageReportRow(
          role: role,
          calls: byRole[role]!.calls,
          input: byRole[role]!.input,
          output: byRole[role]!.output,
          cacheRead: byRole[role]!.cacheRead,
          cacheWrite: byRole[role]!.cacheWrite,
        ),
    ],
  );
}

class _Acc {
  int calls = 0;
  int input = 0;
  int output = 0;
  int cacheRead = 0;
  int cacheWrite = 0;
}
