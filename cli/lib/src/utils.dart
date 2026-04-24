/// Small extension helpers to keep magic numbers and copy-pasted helpers
/// readable at call sites. Not a utility dumping ground — only add
/// extensions here when they meaningfully clarify a real call site
/// (hardcoded byte counts, hardcoded durations, a stringified [DateTime]
/// "how long ago" rendering) and at least two sites will benefit.
library;

extension ByteUnits on num {
  int get bytes => (this * 1).round();
  int get kilobytes => (this * 1024).round();
  int get megabytes => (this * 1024 * 1024).round();
  int get gigabytes => (this * 1024 * 1024 * 1024).round();
}

extension DurationUnits on num {
  Duration get milliseconds => Duration(milliseconds: round());
  Duration get seconds => Duration(seconds: round());
  Duration get minutes => Duration(minutes: round());
  Duration get hours => Duration(hours: round());
}

extension PercentageUnits on num {
  double get percent => this / 100.0;
}

extension CountUnits on num {
  int get items => round();
}

extension TimeAgo on DateTime {
  /// Short human-facing phrasing of how long ago this timestamp was.
  ///
  /// - Under a minute: "just now"
  /// - Under an hour: "Nm ago"
  /// - Under a day: "Nh ago"
  /// - Under a week: "Nd ago"
  /// - Beyond a week: ISO date (YYYY-MM-DD)
  String get timeAgo {
    final diff = DateTime.now().difference(this);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return toIso8601String().substring(0, 10);
  }
}
