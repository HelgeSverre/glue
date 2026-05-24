import 'package:dart_mappable/dart_mappable.dart';

class UriMapper extends SimpleMapper<Uri> {
  const UriMapper();

  @override
  Uri decode(dynamic value) {
    if (value is Uri) return value;
    if (value is String) return Uri.parse(value);
    throw MapperException.unknownType(value.runtimeType);
  }

  @override
  dynamic encode(Uri self) => self.toString();
}

class DurationMapper extends SimpleMapper<Duration> {
  const DurationMapper();

  @override
  Duration decode(dynamic value) {
    if (value is Duration) return value;
    if (value is int) return Duration(milliseconds: value);
    if (value is String) {
      return Duration(milliseconds: int.parse(value));
    }
    throw MapperException.unknownType(value.runtimeType);
  }

  @override
  dynamic encode(Duration self) => self.inMilliseconds;
}
