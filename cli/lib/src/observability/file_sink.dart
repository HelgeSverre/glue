import 'dart:convert';
import 'dart:io';

import 'package:glue/src/observability/observability.dart';
import 'package:path/path.dart' as p;

class FileSink extends ObservabilitySink {
  final IOSink _sink;

  FileSink({required String logsDir})
      : _sink = (File(p.join(
            logsDir,
            'spans-${DateTime.now().toIso8601String().substring(0, 10)}.jsonl',
          ))
              ..parent.createSync(recursive: true))
            .openWrite(mode: FileMode.append);

  @override
  void onSpan(ObservabilitySpan span) {
    _sink.writeln(jsonEncode(span.toMap()));
  }

  @override
  Future<void> flush() => _sink.flush();

  @override
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}
