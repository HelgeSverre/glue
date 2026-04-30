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

/// Formats [UsageReport] for the `/usage` slash command. Pure function;
/// the action impl in `command_helpers.dart` is a thin shell over it.
String formatUsageReport(UsageReport report) {
  if (report.rows.isEmpty) {
    return 'No LLM calls recorded yet for this session.';
  }

  final buf = StringBuffer();
  buf.writeln('Token usage');
  if (report.modelLabel != null) {
    buf.writeln('  Model:        ${report.modelLabel}');
  }
  if (report.sessionId != null) {
    buf.writeln('  Session:      ${report.sessionId}');
  }
  buf.writeln('  LLM calls:    ${report.totalCalls}');
  buf.writeln('  Total tokens: ${_thousands(report.totalTokens)}');

  final hit = report.cacheHitRate;
  if (hit != null &&
      (report.totalCacheRead > 0 || report.totalCacheWrite > 0)) {
    final pct = (hit * 100).toStringAsFixed(1);
    final billed = report.totalInput + report.totalCacheRead;
    buf.writeln(
      '  Cache hit:    $pct% '
      '(${_thousands(report.totalCacheRead)} of ${_thousands(billed)} '
      'input tokens served from cache)',
    );
  }
  buf.writeln();
  buf.writeln('By role');
  buf.write(_renderTable(report.rows));
  return buf.toString();
}

String _renderTable(List<UsageReportRow> rows) {
  const headers = ['role', 'calls', 'input', 'output', 'cache rd', 'cache wr'];
  final cells = [
    for (final r in rows)
      [
        r.role,
        '${r.calls}',
        _thousands(r.input),
        _thousands(r.output),
        _thousands(r.cacheRead),
        _thousands(r.cacheWrite),
      ],
  ];

  // Column widths — max of header and any cell in that column.
  final widths = List<int>.generate(headers.length, (col) {
    var w = headers[col].length;
    for (final row in cells) {
      if (row[col].length > w) w = row[col].length;
    }
    return w;
  });

  String line(String left, String mid, String right, String fill) {
    final segs = [for (final w in widths) fill * (w + 2)];
    return '$left${segs.join(mid)}$right\n';
  }

  String rowText(List<String> row) {
    final pieces = [
      // role left-aligned; numeric cols right-aligned.
      ' ${row[0].padRight(widths[0])} ',
      for (var i = 1; i < row.length; i++) ' ${row[i].padLeft(widths[i])} ',
    ];
    return '│${pieces.join('│')}│\n';
  }

  final buf = StringBuffer();
  buf.write(line('  ┌', '┬', '┐', '─'));
  buf.write('  ${rowText(headers)}');
  buf.write(line('  ├', '┼', '┤', '─'));
  for (final row in cells) {
    buf.write('  ${rowText(row)}');
  }
  buf.write(line('  └', '┴', '┘', '─'));
  return buf.toString();
}

String _thousands(int value) {
  final neg = value < 0;
  final s = value.abs().toString();
  final groups = <String>[];
  for (var i = s.length; i > 0; i -= 3) {
    final start = i - 3 < 0 ? 0 : i - 3;
    groups.insert(0, s.substring(start, i));
  }
  return '${neg ? '-' : ''}${groups.join(',')}';
}
