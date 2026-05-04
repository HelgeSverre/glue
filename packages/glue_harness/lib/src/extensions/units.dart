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
