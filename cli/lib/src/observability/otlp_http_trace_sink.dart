import 'dart:async';
import 'dart:convert';

import 'package:glue/src/config/constants.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:http/http.dart' as http;

/// Exports completed Glue spans using OTLP/HTTP JSON.
class OtlpHttpTraceSink extends ObservabilitySink {
  OtlpHttpTraceSink({
    required OtelConfig config,
    http.Client? client,
    DateTime Function()? now,
    int maxBatchSize = 64,
  })  : _config = config,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = now ?? DateTime.now,
        _maxBatchSize = maxBatchSize;

  final OtelConfig _config;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final int _maxBatchSize;
  final List<ObservabilitySpan> _buffer = [];
  Future<void>? _pendingFlush;
  bool _closed = false;

  @override
  void onSpan(ObservabilitySpan span) {
    if (_closed || !_config.isConfigured) return;
    _buffer.add(span);
    if (_buffer.length >= _maxBatchSize) {
      _pendingFlush ??= _flushNow().whenComplete(() => _pendingFlush = null);
    }
  }

  @override
  Future<void> flush() async {
    final pending = _pendingFlush;
    if (pending != null) await pending;
    await _flushNow();
  }

  Future<void> _flushNow() async {
    if (_closed || _buffer.isEmpty || !_config.isConfigured) return;

    final spans = List<ObservabilitySpan>.from(_buffer);
    _buffer.clear();
    final endpoint = normalizeOtlpTracesEndpoint(_config.endpoint!);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._config.headers,
    };

    try {
      await _client
          .post(
            endpoint,
            headers: headers,
            body: jsonEncode(_toOtlpPayload(spans)),
          )
          .timeout(Duration(milliseconds: _config.timeoutMilliseconds));
    } on Object {
      // Tracing must never affect the agent loop. Keep local JSONL as the
      // durable fallback if the remote collector is down or misconfigured.
    }
  }

  @override
  Future<void> close() async {
    await flush();
    _closed = true;
    if (_ownsClient) _client.close();
  }

  Map<String, dynamic> _toOtlpPayload(List<ObservabilitySpan> spans) {
    return {
      'resourceSpans': [
        {
          'resource': {
            'attributes': [
              _kv('service.name', _config.serviceName),
              _kv('service.version', AppConstants.version),
              _kv('telemetry.sdk.language', 'dart'),
              _kv('telemetry.sdk.name', 'glue'),
              for (final entry in _config.resourceAttributes.entries)
                _kv(entry.key, entry.value),
            ],
          },
          'scopeSpans': [
            {
              'scope': {
                'name': 'glue',
                'version': AppConstants.version,
              },
              'spans': spans.map(_spanToOtlp).toList(),
            }
          ],
        }
      ],
    };
  }

  Map<String, dynamic> _spanToOtlp(ObservabilitySpan span) {
    return {
      'traceId': span.traceId,
      'spanId': span.spanId,
      if (span.parentSpanId != null) 'parentSpanId': span.parentSpanId,
      'name': span.name,
      'kind': _spanKind(span.kind),
      'startTimeUnixNano': _unixNanos(span.start),
      'endTimeUnixNano': _unixNanos(span.endTime ?? _now()),
      'attributes': [
        _kv('glue.span.kind', span.kind),
        for (final entry in span.attributes.entries)
          if (_attributeSupported(entry.value))
            _kv(entry.key, entry.value as Object),
      ],
      if (span.events.isNotEmpty)
        'events': [
          for (final event in span.events)
            {
              'name': event.name,
              'timeUnixNano': _unixNanos(event.timestamp),
              if (event.attributes.isNotEmpty)
                'attributes': [
                  for (final entry in event.attributes.entries)
                    if (_attributeSupported(entry.value))
                      _kv(entry.key, entry.value as Object),
                ],
            }
        ],
      'status': {
        'code': switch (span.statusCode) {
          'ok' => 'STATUS_CODE_OK',
          'error' => 'STATUS_CODE_ERROR',
          _ => 'STATUS_CODE_UNSET',
        },
        if (span.statusMessage != null) 'message': span.statusMessage,
      },
    };
  }
}

Uri normalizeOtlpTracesEndpoint(String raw) {
  final uri = Uri.parse(raw.trim());
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  if (path.endsWith('/v1/traces')) return uri;
  return uri.replace(path: '$path/v1/traces');
}

String redactOtelHeadersForDisplay(Map<String, String> headers) {
  if (headers.isEmpty) return '(none)';
  return headers.keys.join(', ');
}

Map<String, dynamic> _kv(String key, Object value) => {
      'key': key,
      'value': _anyValue(value),
    };

Map<String, dynamic> _anyValue(Object value) {
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'boolValue': value};
  if (value is int) return {'intValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is List<String>) {
    return {
      'arrayValue': {
        'values': [for (final item in value) _anyValue(item)],
      },
    };
  }
  if (value is List<int>) {
    return {
      'arrayValue': {
        'values': [for (final item in value) _anyValue(item)],
      },
    };
  }
  if (value is List<double>) {
    return {
      'arrayValue': {
        'values': [for (final item in value) _anyValue(item)],
      },
    };
  }
  if (value is List<bool>) {
    return {
      'arrayValue': {
        'values': [for (final item in value) _anyValue(item)],
      },
    };
  }
  return {'stringValue': value.toString()};
}

bool _attributeSupported(Object? value) {
  if (value == null) return false;
  if (value is String || value is bool || value is int || value is double) {
    return true;
  }
  if (value is List) {
    return value.every((item) =>
        item is String || item is bool || item is int || item is double);
  }
  return true;
}

String _spanKind(String kind) {
  if (kind.startsWith('http')) return 'SPAN_KIND_CLIENT';
  return 'SPAN_KIND_INTERNAL';
}

String _unixNanos(DateTime time) {
  final micros = time.toUtc().microsecondsSinceEpoch;
  return (BigInt.from(micros) * BigInt.from(1000)).toString();
}
