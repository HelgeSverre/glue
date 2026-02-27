import 'dart:io';
import '../config/constants.dart';
import 'package:path/path.dart' as p;

class DebugLogger {
  final IOSink? _sink;
  final bool enabled;

  DebugLogger({required String logsDir, this.enabled = true})
      : _sink = enabled
            ? (File(p.join(
                logsDir,
                'debug-${DateTime.now().toIso8601String().substring(0, 10)}.log',
              ))
                  ..parent.createSync(recursive: true))
                .openWrite(mode: FileMode.append)
            : null {
    if (enabled) {
      _sink!.writeln(
          '--- Session started ${DateTime.now().toIso8601String()} ---');
    }
  }

  void log(String category, String message) {
    if (!enabled || _sink == null) return;
    final ts = DateTime.now().toIso8601String();
    _sink.writeln('[$ts] [$category] $message');
  }

  void logHttp(String method, String url, int statusCode, {String? body}) {
    log('HTTP', '$method $url → $statusCode');
    if (body != null && body.length < AppConstants.debugLogBodySizeLimit) {
      log('HTTP', 'Body: $body');
    }
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
