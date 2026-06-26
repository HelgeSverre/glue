/// Compact, single-column token count: `999`, `1.2k`, `42k`.
String formatCompactTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${n ~/ 1000}.${(n % 1000) ~/ 100}k';
  return '${n ~/ 1000}k';
}

/// Context-occupancy gauge: `14k/131k ctx (11%)`. Numerator is the latest
/// turn's billed input (what the model saw); denominator is the resolved
/// context window. Returns `null` — so the caller omits the segment — when
/// the window is unknown/non-positive or no turn has run yet.
String? formatContextGauge(int used, int? window) {
  if (window == null || window <= 0 || used <= 0) return null;
  final pct = (used * 100 / window).round();
  return '${formatCompactTokens(used)}/${formatCompactTokens(window)} '
      'ctx ($pct%)';
}
