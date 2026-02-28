import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';

final _eventRandom = Random.secure();

String _uuid4() {
  final bytes = List.generate(16, (_) => _eventRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class LangfuseSink extends ObservabilitySink {
  final LangfuseConfig _config;
  final http.Client _httpClient;
  final List<ObservabilitySpan> _buffer = [];

  LangfuseSink({
    required LangfuseConfig config,
    http.Client? httpClient,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client();

  @override
  void onSpan(ObservabilitySpan span) {
    _buffer.add(span);
  }

  @override
  Future<void> flush() async {
    if (_buffer.isEmpty || !_config.isConfigured) return;
    final spans = List<ObservabilitySpan>.from(_buffer);
    _buffer.clear();
    try {
      final auth = base64Encode(
        utf8.encode('${_config.publicKey}:${_config.secretKey}'),
      );

      final batch = <Map<String, dynamic>>[];
      for (final span in spans) {
        batch.addAll(_spanToLangfuseEvents(span));
      }

      final response = await _httpClient.post(
        Uri.parse('${_config.baseUrl}/api/public/ingestion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $auth',
        },
        body: jsonEncode({'batch': batch}),
      );
      if (response.statusCode >= 400) {
        _buffer.insertAll(0, spans);
        stderr.writeln(
          'glue: langfuse export failed (${response.statusCode})',
        );
      }
    } catch (e) {
      _buffer.insertAll(0, spans);
      stderr.writeln('glue: langfuse export error: $e');
    }
  }

  @override
  Future<void> close() async {
    await flush();
  }

  List<Map<String, dynamic>> _spanToLangfuseEvents(ObservabilitySpan span) {
    final now = DateTime.now().toUtc().toIso8601String();

    // LLM spans map to generation-create; others map to span-create.
    if (span.kind == 'llm') {
      return [
        {
          'id': _uuid4(),
          'timestamp': now,
          'type': 'generation-create',
          'body': {
            'id': span.spanId,
            'traceId': span.traceId,
            'name': span.name,
            'startTime': span.start.toUtc().toIso8601String(),
            if (span.endTime != null)
              'endTime': span.endTime!.toUtc().toIso8601String(),
            if (span.parentSpanId != null)
              'parentObservationId': span.parentSpanId,
            if (span.attributes['input_tokens'] != null ||
                span.attributes['output_tokens'] != null)
              'usage': {
                if (span.attributes['input_tokens'] != null)
                  'input': span.attributes['input_tokens'],
                if (span.attributes['output_tokens'] != null)
                  'output': span.attributes['output_tokens'],
              },
            'metadata': Map<String, dynamic>.from(span.attributes)
              ..remove('input_tokens')
              ..remove('output_tokens')
              ..remove('error'),
            if (span.attributes.containsKey('error'))
              'level': 'ERROR'
            else
              'level': 'DEFAULT',
            if (span.attributes.containsKey('error'))
              'statusMessage': span.attributes['error'].toString(),
          },
        }
      ];
    }

    return [
      {
        'id': _uuid4(),
        'timestamp': now,
        'type': 'span-create',
        'body': {
          'id': span.spanId,
          'traceId': span.traceId,
          'name': span.name,
          'startTime': span.start.toUtc().toIso8601String(),
          if (span.endTime != null)
            'endTime': span.endTime!.toUtc().toIso8601String(),
          if (span.parentSpanId != null)
            'parentObservationId': span.parentSpanId,
          'metadata': Map<String, dynamic>.from(span.attributes)
            ..remove('error'),
          if (span.attributes.containsKey('error'))
            'level': 'ERROR'
          else
            'level': 'DEFAULT',
          if (span.attributes.containsKey('error'))
            'statusMessage': span.attributes['error'].toString(),
        },
      }
    ];
  }
}
