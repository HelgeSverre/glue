/// Compact, single-column token count: `999`, `1.2k`, `42k`.
String formatCompactTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${n ~/ 1000}.${(n % 1000) ~/ 100}k';
  return '${n ~/ 1000}k';
}
