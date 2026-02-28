import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';

class LangfuseSink extends ObservabilitySink {
  final LangfuseConfig _config;
  final http.Client _httpClient;
  final List<Map<String, dynamic>> _buffer = [];

  LangfuseSink({
    required LangfuseConfig config,
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
    final events = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      final auth = base64Encode(
        utf8.encode('${_config.publicKey}:${_config.secretKey}'),
      );
      await _httpClient.post(
        Uri.parse('${_config.baseUrl}/api/public/ingestion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $auth',
        },
        body: jsonEncode({'batch': events}),
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
