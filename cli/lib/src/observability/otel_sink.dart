import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';

class OtelSink extends ObservabilitySink {
  final OtelConfig _config;
  final http.Client _httpClient;
  final List<Map<String, dynamic>> _buffer = [];

  OtelSink({
    required OtelConfig config,
    http.Client? httpClient,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client();

  @override
  void onSpan(ObservabilitySpan span) {
    _buffer.add(span.toMap());
  }

  @override
  Future<void> flush() async {
    if (_buffer.isEmpty || !_config.isConfigured) return;
    final spans = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      await _httpClient.post(
        Uri.parse(_config.endpoint!),
        headers: {
          'Content-Type': 'application/json',
          ..._config.headers,
        },
        body: jsonEncode({
          'resourceSpans': [
            {
              'scopeSpans': [
                {'spans': spans}
              ]
            }
          ]
        }),
      );
    } catch (_) {
      // Best-effort; don't crash the app.
    }
  }

  @override
  Future<void> close() async {
    await flush();
  }
}
