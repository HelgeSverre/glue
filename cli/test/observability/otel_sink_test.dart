import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/observability/otel_sink.dart';
import 'package:test/test.dart';

class _MockHttpClient extends http.BaseClient {
  int statusCode = 200;
  bool shouldThrow = false;
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) {
      bodies.add(request.body);
    }
    if (shouldThrow) throw Exception('network error');
    return http.StreamedResponse(
      Stream.value([]),
      statusCode,
    );
  }
}

OtelConfig _configured() => const OtelConfig(
      enabled: true,
      endpoint: 'https://otel.example.com/v1/traces',
      headers: {'Authorization': 'Bearer token123'},
    );

void main() {
  late _MockHttpClient mockHttp;

  setUp(() {
    mockHttp = _MockHttpClient();
  });

  test('buffers spans and sends on flush', () async {
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(mockHttp.requests, hasLength(1));
    expect(mockHttp.bodies, hasLength(1));
  });

  test('skips flush when buffer is empty', () async {
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);

    await sink.flush();

    expect(mockHttp.requests, isEmpty);
  });

  test('skips flush when not configured', () async {
    final sink = OtelSink(
      config: const OtelConfig(enabled: false),
      httpClient: mockHttp,
    );
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(mockHttp.requests, isEmpty);
  });

  test('sends correct OTLP JSON structure', () async {
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'my-span', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
    final resourceSpans = payload['resourceSpans'] as List<dynamic>;
    expect(resourceSpans, hasLength(1));

    final rs = resourceSpans[0] as Map<String, dynamic>;
    final resource = rs['resource'] as Map<String, dynamic>;
    final attrs = resource['attributes'] as List<dynamic>;
    final firstAttr = attrs.first as Map<String, dynamic>;
    expect(firstAttr['key'], 'service.name');
    expect(
      (firstAttr['value'] as Map<String, dynamic>)['stringValue'],
      'glue-cli',
    );

    final scopeSpans = rs['scopeSpans'] as List<dynamic>;
    expect(scopeSpans, hasLength(1));
    final ss = scopeSpans[0] as Map<String, dynamic>;
    final scope = ss['scope'] as Map<String, dynamic>;
    expect(scope['name'], 'glue.observability');

    final spans = ss['spans'] as List<dynamic>;
    expect(spans, hasLength(1));
  });

  group('span mapping', () {
    test('traceId and spanId are mapped correctly', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final otlpSpan = _extractFirstSpan(payload);
      expect(otlpSpan['traceId'], span.traceId);
      expect(otlpSpan['spanId'], span.spanId);
      expect(otlpSpan['name'], 'test');
    });

    test('http kind maps to 3 (CLIENT)', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'http GET', kind: 'http');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['kind'], 3);
    });

    test('llm kind maps to 3 (CLIENT)', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'llm.stream', kind: 'llm');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['kind'], 3);
    });

    test('tool kind maps to 1 (INTERNAL)', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'tool.read', kind: 'tool');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['kind'], 1);
    });

    test('unknown kind maps to 1 (INTERNAL)', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'custom', kind: 'custom');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['kind'], 1);
    });

    test('startTimeUnixNano is a string', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['startTimeUnixNano'], isA<String>());
      expect(int.tryParse(otlpSpan['startTimeUnixNano'] as String), isNotNull);
    });

    test('endTimeUnixNano is present when span ended', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['endTimeUnixNano'], isA<String>());
    });

    test('parentSpanId included when set', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'child',
        kind: 'internal',
        parentSpanId: 'parent123',
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan['parentSpanId'], 'parent123');
    });

    test('parentSpanId omitted when null', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'root', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      expect(otlpSpan.containsKey('parentSpanId'), isFalse);
    });
  });

  group('attribute mapping', () {
    test('int maps to intValue string', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'count': 42},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      final attr = _findAttribute(otlpSpan, 'count');
      expect((attr['value'] as Map<String, dynamic>)['intValue'], '42');
    });

    test('string maps to stringValue', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'method': 'GET'},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      final attr = _findAttribute(otlpSpan, 'method');
      expect((attr['value'] as Map<String, dynamic>)['stringValue'], 'GET');
    });

    test('bool maps to boolValue', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'success': true},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      final attr = _findAttribute(otlpSpan, 'success');
      expect((attr['value'] as Map<String, dynamic>)['boolValue'], true);
    });

    test('double maps to doubleValue', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'ratio': 0.75},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      final attr = _findAttribute(otlpSpan, 'ratio');
      expect((attr['value'] as Map<String, dynamic>)['doubleValue'], 0.75);
    });
  });

  group('status', () {
    test('error span has code 2 with message', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'error': 'something went wrong'},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      final status = otlpSpan['status'] as Map<String, dynamic>;
      expect(status['code'], 2);
      expect(status['message'], 'something went wrong');
    });

    test('success span has code 1', () async {
      final sink = OtelSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final otlpSpan = _extractFirstSpan(
          jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>);
      final status = otlpSpan['status'] as Map<String, dynamic>;
      expect(status['code'], 1);
      expect(status.containsKey('message'), isFalse);
    });
  });

  test('sends with configured headers', () async {
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    final request = mockHttp.requests.first;
    expect(request.headers['Content-Type'], 'application/json');
    expect(request.headers['Authorization'], 'Bearer token123');
  });

  test('posts to configured endpoint', () async {
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(
      mockHttp.requests.first.url.toString(),
      'https://otel.example.com/v1/traces',
    );
  });

  test('re-enqueues buffer on HTTP failure', () async {
    mockHttp.statusCode = 500;
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(mockHttp.requests, hasLength(1));

    mockHttp.statusCode = 200;
    await sink.flush();

    expect(mockHttp.requests, hasLength(2));
  });

  test('re-enqueues buffer on network exception', () async {
    mockHttp.shouldThrow = true;
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(mockHttp.requests, hasLength(1));

    mockHttp.shouldThrow = false;
    await sink.flush();

    expect(mockHttp.requests, hasLength(2));
  });

  test('calls onError callback on HTTP failure', () async {
    mockHttp.statusCode = 500;
    final errors = <String>[];
    final sink = OtelSink(
      config: _configured(),
      httpClient: mockHttp,
      onError: errors.add,
    );
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(errors, hasLength(1));
    expect(errors.first, contains('otel export failed'));
    expect(errors.first, contains('500'));
  });

  test('calls onError callback on network exception', () async {
    mockHttp.shouldThrow = true;
    final errors = <String>[];
    final sink = OtelSink(
      config: _configured(),
      httpClient: mockHttp,
      onError: errors.add,
    );
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(errors, hasLength(1));
    expect(errors.first, contains('otel export error'));
  });

  test('does not write to stderr when onError is null', () async {
    mockHttp.shouldThrow = true;
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    // Should not throw or write to stderr.
    await sink.flush();

    // Span was re-enqueued for retry.
    mockHttp.shouldThrow = false;
    await sink.flush();
    expect(mockHttp.requests, hasLength(2));
  });

  test('close calls flush', () async {
    final sink = OtelSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.close();

    expect(mockHttp.requests, hasLength(1));
  });
}

Map<String, dynamic> _extractFirstSpan(Map<String, dynamic> payload) {
  final resourceSpans = payload['resourceSpans'] as List<dynamic>;
  final rs = resourceSpans[0] as Map<String, dynamic>;
  final scopeSpans = rs['scopeSpans'] as List<dynamic>;
  final ss = scopeSpans[0] as Map<String, dynamic>;
  final spans = ss['spans'] as List<dynamic>;
  return spans[0] as Map<String, dynamic>;
}

Map<String, dynamic> _findAttribute(Map<String, dynamic> otlpSpan, String key) {
  final attrs = otlpSpan['attributes'] as List<dynamic>;
  return attrs.firstWhere(
    (a) => (a as Map<String, dynamic>)['key'] == key,
  ) as Map<String, dynamic>;
}
