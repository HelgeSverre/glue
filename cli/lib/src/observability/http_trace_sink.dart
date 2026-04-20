import 'dart:convert';
import 'dart:io';

import 'package:glue/src/observability/observability.dart';
import 'package:path/path.dart' as p;

/// Writes only `http.*`-kind spans to `logs/http-YYYY-MM-DD.jsonl`.
///
/// Runs alongside [FileSink] which captures everything else. The split keeps
/// the generic span log readable and lets maintainers tail HTTP traffic
/// without noise from agent-level spans.
class HttpTraceSink extends ObservabilitySink {
  final IOSink _sink;

  HttpTraceSink({required String logsDir})
      : _sink = (File(p.join(
          logsDir,
          'http-${DateTime.now().toIso8601String().substring(0, 10)}.jsonl',
        ))
              ..parent.createSync(recursive: true))
            .openWrite(mode: FileMode.append);

  @override
  void onSpan(ObservabilitySpan span) {
    if (!span.kind.startsWith('http')) return;
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
