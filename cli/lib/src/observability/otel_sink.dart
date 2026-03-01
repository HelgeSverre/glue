import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';

class OtelSink extends ObservabilitySink {
  final OtelConfig _config;
  final http.Client _httpClient;
  final int maxBufferSize;
  final Map<String, String> resourceAttributes;
  final void Function(String message)? onError;
  final List<ObservabilitySpan> _buffer = [];

  OtelSink({
    required OtelConfig config,
    http.Client? httpClient,
    this.maxBufferSize = 1000,
    this.resourceAttributes = const {},
    this.onError,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client();

  @override
  void onSpan(ObservabilitySpan span) {
    _buffer.add(span);
    if (_buffer.length > maxBufferSize) {
      _buffer.removeRange(0, _buffer.length - maxBufferSize);
    }
  }

  @override
  Future<void> flush() async {
    if (_buffer.isEmpty || !_config.isConfigured) return;
    final spans = List<ObservabilitySpan>.from(_buffer);
    _buffer.clear();
    try {
      final response = await _httpClient.post(
        Uri.parse(_config.endpoint!),
        headers: {
          'Content-Type': 'application/json',
          ..._config.headers,
        },
        body: jsonEncode(_buildPayload(spans)),
      );
      if (response.statusCode >= 400) {
        // Re-enqueue on server error for retry on next flush.
        _buffer.insertAll(0, spans);
        if (_buffer.length > maxBufferSize) {
          _buffer.removeRange(0, _buffer.length - maxBufferSize);
        }
        onError?.call(
          'glue: otel export failed (${response.statusCode})',
        );
      }
    } catch (e) {
      // Re-enqueue for retry on next flush.
      _buffer.insertAll(0, spans);
      if (_buffer.length > maxBufferSize) {
        _buffer.removeRange(0, _buffer.length - maxBufferSize);
      }
      onError?.call('glue: otel export error: $e');
    }
  }

  @override
  Future<void> close() async {
    await flush();
  }

  Map<String, dynamic> _buildPayload(List<ObservabilitySpan> spans) {
    return {
      'resourceSpans': [
        {
          'resource': {
            'attributes': [
              _stringAttr('service.name', 'glue-cli'),
              for (final e in resourceAttributes.entries)
                _stringAttr(e.key, e.value),
            ],
          },
          'scopeSpans': [
            {
              'scope': {'name': 'glue.observability', 'version': '1.0.0'},
              'spans': spans.map(_spanToOtlp).toList(),
            }
          ],
        }
      ],
    };
  }

  Map<String, dynamic> _spanToOtlp(ObservabilitySpan span) {
    final otlpKind = switch (span.kind) {
      'http' => 3, // CLIENT
      'llm' => 3, // CLIENT
      'tool' => 1, // INTERNAL
      _ => 1, // INTERNAL
    };

    final hasError = span.attributes.containsKey('error');

    return {
      'traceId': span.traceId,
      'spanId': span.spanId,
      if (span.parentSpanId != null) 'parentSpanId': span.parentSpanId,
      'name': span.name,
      'kind': otlpKind,
      'startTimeUnixNano': '${span.start.microsecondsSinceEpoch * 1000}',
      if (span.endTime != null)
        'endTimeUnixNano': '${span.endTime!.microsecondsSinceEpoch * 1000}',
      'attributes': span.attributes.entries
          .map((e) => _toOtlpAttr(e.key, e.value))
          .toList(),
      'status': {
        'code': hasError ? 2 : 1, // ERROR or OK
        if (hasError) 'message': span.attributes['error'].toString(),
      },
    };
  }

  static Map<String, dynamic> _toOtlpAttr(String key, dynamic value) {
    return {
      'key': key,
      'value': switch (value) {
        final int v => {'intValue': '$v'},
        final double v => {'doubleValue': v},
        final bool v => {'boolValue': v},
        final String v => {'stringValue': v},
        _ => {'stringValue': value.toString()},
      },
    };
  }

  static Map<String, dynamic> _stringAttr(String key, String value) => {
        'key': key,
        'value': {'stringValue': value},
      };
}
