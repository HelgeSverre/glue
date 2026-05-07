/// Compact relative-time labels for `DateTime`.
extension TimeAgoX on DateTime {
  /// Compact relative-time label suitable for table cells: `just now`,
  /// `15m ago`, `4h ago`, `3d ago`, or an ISO date past one week.
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return toIso8601String().substring(0, 10);
  }
}
