import 'package:glue_core/glue_core.dart';

/// Formats a [UsageReport] for the `/usage` slash command. Pure
/// function. The aggregator + data types live in glue_harness so the
/// ACP server and session-resume header can use them too.
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
