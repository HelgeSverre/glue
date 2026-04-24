import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/generated/opentelemetry/proto/collector/trace/v1/trace_service.pb.dart'
    as $collector;
import 'package:glue/src/generated/opentelemetry/proto/common/v1/common.pb.dart'
    as $common;
import 'package:glue/src/generated/opentelemetry/proto/resource/v1/resource.pb.dart'
    as $resource;
import 'package:glue/src/generated/opentelemetry/proto/trace/v1/trace.pb.dart'
    as $trace;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:http/http.dart' as http;

/// Exports completed Glue spans using OTLP/HTTP.
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
    final request = switch (_config.protocol) {
      OtelProtocol.httpJson => (
          headers: <String, String>{
            'Content-Type': 'application/json',
            ..._config.headers,
          },
          body: jsonEncode(_toOtlpJsonPayload(spans)),
        ),
      OtelProtocol.httpProtobuf => (
          headers: <String, String>{
            'Content-Type': 'application/x-protobuf',
            ..._config.headers,
          },
          body: _toOtlpProtobufPayload(spans),
        ),
    };

    try {
      await _client
          .post(
            endpoint,
            headers: request.headers,
            body: request.body,
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

  Map<String, dynamic> _toOtlpJsonPayload(List<ObservabilitySpan> spans) {
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
              'spans': spans.map(_spanToOtlpJson).toList(),
            }
          ],
        }
      ],
    };
  }

  Uint8List _toOtlpProtobufPayload(List<ObservabilitySpan> spans) {
    final request = $collector.ExportTraceServiceRequest(
      resourceSpans: [
        $trace.ResourceSpans(
          resource: $resource.Resource(
            attributes: [
              _kvProto('service.name', _config.serviceName),
              _kvProto('service.version', AppConstants.version),
              _kvProto('telemetry.sdk.language', 'dart'),
              _kvProto('telemetry.sdk.name', 'glue'),
              for (final entry in _config.resourceAttributes.entries)
                _kvProto(entry.key, entry.value),
            ],
          ),
          scopeSpans: [
            $trace.ScopeSpans(
              scope: $common.InstrumentationScope(
                name: 'glue',
                version: AppConstants.version,
              ),
              spans: spans.map(_spanToOtlpProto).toList(),
            ),
          ],
        ),
      ],
    );
    return Uint8List.fromList(request.writeToBuffer());
  }

  Map<String, dynamic> _spanToOtlpJson(ObservabilitySpan span) {
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

$common.KeyValue _kvProto(String key, Object value) => $common.KeyValue(
      key: key,
      value: _anyValueProto(value),
    );

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

$common.AnyValue _anyValueProto(Object value) {
  if (value is String) return $common.AnyValue(stringValue: value);
  if (value is bool) return $common.AnyValue(boolValue: value);
  if (value is int) {
    return $common.AnyValue(intValue: $fixnum.Int64(value));
  }
  if (value is double) return $common.AnyValue(doubleValue: value);
  if (value is List<String>) {
    return $common.AnyValue(
      arrayValue: $common.ArrayValue(
        values: value.map(_anyValueProto),
      ),
    );
  }
  if (value is List<int>) {
    return $common.AnyValue(
      arrayValue: $common.ArrayValue(
        values: value.map(_anyValueProto),
      ),
    );
  }
  if (value is List<double>) {
    return $common.AnyValue(
      arrayValue: $common.ArrayValue(
        values: value.map(_anyValueProto),
      ),
    );
  }
  if (value is List<bool>) {
    return $common.AnyValue(
      arrayValue: $common.ArrayValue(
        values: value.map(_anyValueProto),
      ),
    );
  }
  return $common.AnyValue(stringValue: value.toString());
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

$trace.Span_SpanKind _spanKindProto(String kind) {
  if (kind.startsWith('http')) return $trace.Span_SpanKind.SPAN_KIND_CLIENT;
  return $trace.Span_SpanKind.SPAN_KIND_INTERNAL;
}

$trace.Status_StatusCode _statusCodeProto(String? code) {
  return switch (code) {
    'ok' => $trace.Status_StatusCode.STATUS_CODE_OK,
    'error' => $trace.Status_StatusCode.STATUS_CODE_ERROR,
    _ => $trace.Status_StatusCode.STATUS_CODE_UNSET,
  };
}

$trace.Span _spanToOtlpProto(ObservabilitySpan span) {
  return $trace.Span(
    traceId: _hexToBytes(span.traceId),
    spanId: _hexToBytes(span.spanId),
    parentSpanId:
        span.parentSpanId != null ? _hexToBytes(span.parentSpanId!) : null,
    name: span.name,
    kind: _spanKindProto(span.kind),
    startTimeUnixNano: _unixNanosInt64(span.start),
    endTimeUnixNano: _unixNanosInt64(span.endTime ?? DateTime.now()),
    attributes: [
      _kvProto('glue.span.kind', span.kind),
      for (final entry in span.attributes.entries)
        if (_attributeSupported(entry.value))
          _kvProto(entry.key, entry.value as Object),
    ],
    events: [
      for (final event in span.events)
        $trace.Span_Event(
          name: event.name,
          timeUnixNano: _unixNanosInt64(event.timestamp),
          attributes: [
            for (final entry in event.attributes.entries)
              if (_attributeSupported(entry.value))
                _kvProto(entry.key, entry.value as Object),
          ],
        ),
    ],
    status: $trace.Status(
      code: _statusCodeProto(span.statusCode),
      message: span.statusMessage,
    ),
  );
}

String _unixNanos(DateTime time) {
  final micros = time.toUtc().microsecondsSinceEpoch;
  return (BigInt.from(micros) * BigInt.from(1000)).toString();
}

$fixnum.Int64 _unixNanosInt64(DateTime time) {
  final micros = time.toUtc().microsecondsSinceEpoch;
  return $fixnum.Int64(micros) * $fixnum.Int64(1000);
}

Uint8List _hexToBytes(String hex) {
  final normalized = hex.length.isOdd ? '0$hex' : hex;
  final out = Uint8List(normalized.length ~/ 2);
  for (var i = 0; i < normalized.length; i += 2) {
    out[i ~/ 2] = int.parse(normalized.substring(i, i + 2), radix: 16);
  }
  return out;
}
