import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/observability/langfuse_sink.dart';
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

LangfuseConfig _configured() => const LangfuseConfig(
      enabled: true,
      baseUrl: 'https://langfuse.example.com',
      publicKey: 'pk-test',
      secretKey: 'sk-test',
    );

Map<String, dynamic> _findByType(List<dynamic> batch, String type) =>
    batch.cast<Map<String, dynamic>>().firstWhere((e) => e['type'] == type);

List<Map<String, dynamic>> _allByType(List<dynamic> batch, String type) =>
    batch.cast<Map<String, dynamic>>().where((e) => e['type'] == type).toList();

void main() {
  late _MockHttpClient mockHttp;

  setUp(() {
    mockHttp = _MockHttpClient();
  });

  test('buffers spans and sends on flush', () async {
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'tool');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(mockHttp.requests, hasLength(1));
  });

  test('sends with Basic auth header', () async {
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    final expectedAuth = base64Encode(utf8.encode('pk-test:sk-test'));
    expect(
      mockHttp.requests.first.headers['Authorization'],
      'Basic $expectedAuth',
    );
  });

  test('posts to correct endpoint', () async {
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(
      mockHttp.requests.first.url.toString(),
      'https://langfuse.example.com/api/public/ingestion',
    );
  });

  test('skips flush when buffer is empty', () async {
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);

    await sink.flush();

    expect(mockHttp.requests, isEmpty);
  });

  test('skips flush when not configured', () async {
    final sink = LangfuseSink(
      config: const LangfuseConfig(enabled: false),
      httpClient: mockHttp,
    );
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(mockHttp.requests, isEmpty);
  });

  group('trace-create events', () {
    test('emits trace-create for new traceId', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);
      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final traceEvent = _findByType(batch, 'trace-create');
      final body = traceEvent['body'] as Map<String, dynamic>;
      expect(body['id'], span.traceId);
      expect(body['name'], 'test');
    });

    test('emits trace-create only once per traceId', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span1 = ObservabilitySpan(
        name: 'span1',
        kind: 'internal',
        traceId: 'shared-trace',
      );
      span1.end();
      sink.onSpan(span1);
      final span2 = ObservabilitySpan(
        name: 'span2',
        kind: 'tool',
        traceId: 'shared-trace',
      );
      span2.end();
      sink.onSpan(span2);
      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final traceEvents = _allByType(batch, 'trace-create');
      expect(traceEvents, hasLength(1));
      final traceBody = traceEvents[0]['body'] as Map<String, dynamic>;
      expect(traceBody['id'], 'shared-trace');
    });

    test('trace-create includes resource attributes', () async {
      final sink = LangfuseSink(
        config: _configured(),
        httpClient: mockHttp,
        resourceAttributes: {
          'glue.session.id': 'sess-123',
          'gen_ai.system': 'anthropic',
          'gen_ai.request.model': 'claude-3.5-sonnet',
          'deployment.environment.name': 'dev',
          'service.version': '0.1.0',
        },
      );
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);
      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final traceEvent = _findByType(batch, 'trace-create');
      final body = traceEvent['body'] as Map<String, dynamic>;
      expect(body['sessionId'], 'sess-123');
      expect(body['environment'], 'dev');
      expect(body['release'], '0.1.0');
      final tags = body['tags'] as List;
      expect(tags, contains('provider:anthropic'));
      expect(tags, contains('model:claude-3.5-sonnet'));
    });
  });

  group('LLM spans', () {
    test('produce generation-create events', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'llm.stream',
        kind: 'llm',
        attributes: {'message_count': 3},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      expect(batch, hasLength(2));
      final event = _findByType(batch, 'generation-create');
      expect(event['type'], 'generation-create');
    });

    test('include usage fields from token counts', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'llm.stream',
        kind: 'llm',
        attributes: {'input_tokens': 100, 'output_tokens': 50},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body = _findByType(batch, 'generation-create')['body']
          as Map<String, dynamic>;
      final usage = body['usage'] as Map<String, dynamic>;
      expect(usage['input'], 100);
      expect(usage['output'], 50);
    });

    test('exclude token counts from metadata', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'llm.stream',
        kind: 'llm',
        attributes: {
          'input_tokens': 100,
          'output_tokens': 50,
          'model': 'gpt-4',
        },
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body = _findByType(batch, 'generation-create')['body']
          as Map<String, dynamic>;
      final metadata = body['metadata'] as Map<String, dynamic>;
      expect(metadata.containsKey('input_tokens'), isFalse);
      expect(metadata.containsKey('output_tokens'), isFalse);
      expect(metadata['model'], 'gpt-4');
    });
  });

  group('non-LLM spans', () {
    test('produce span-create events', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'tool.read', kind: 'tool');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      expect(batch, hasLength(2));
      final event = _findByType(batch, 'span-create');
      expect(event['type'], 'span-create');
    });

    test('http spans produce span-create events', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'http GET', kind: 'http');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final event = _findByType(batch, 'span-create');
      expect(event['type'], 'span-create');
    });
  });

  group('event envelope', () {
    test('has id, timestamp, type, and body', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final event = _findByType(batch, 'span-create');
      expect(event.containsKey('id'), isTrue);
      expect(event['id'], isA<String>());
      expect((event['id'] as String).length, 36);
      expect(event.containsKey('timestamp'), isTrue);
      expect(event.containsKey('type'), isTrue);
      expect(event.containsKey('body'), isTrue);
    });

    test('body includes traceId, spanId, startTime, endTime', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body =
          _findByType(batch, 'span-create')['body'] as Map<String, dynamic>;
      expect(body['id'], span.spanId);
      expect(body['traceId'], span.traceId);
      expect(body['name'], 'test');
      expect(body.containsKey('startTime'), isTrue);
      expect(body.containsKey('endTime'), isTrue);
    });

    test('body includes parentObservationId when parentSpanId set', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'child',
        kind: 'internal',
        parentSpanId: 'parent-abc',
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body =
          _findByType(batch, 'span-create')['body'] as Map<String, dynamic>;
      expect(body['parentObservationId'], 'parent-abc');
    });

    test('body omits parentObservationId when no parent', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'root', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body =
          _findByType(batch, 'span-create')['body'] as Map<String, dynamic>;
      expect(body.containsKey('parentObservationId'), isFalse);
    });
  });

  group('error handling', () {
    test('error spans set level to ERROR with statusMessage', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'error': 'something failed'},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body =
          _findByType(batch, 'span-create')['body'] as Map<String, dynamic>;
      expect(body['level'], 'ERROR');
      expect(body['statusMessage'], 'something failed');
    });

    test('success spans set level to DEFAULT', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(name: 'test', kind: 'internal');
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body =
          _findByType(batch, 'span-create')['body'] as Map<String, dynamic>;
      expect(body['level'], 'DEFAULT');
      expect(body.containsKey('statusMessage'), isFalse);
    });

    test('error LLM spans set level to ERROR', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'llm.stream',
        kind: 'llm',
        attributes: {'error': 'timeout'},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body = _findByType(batch, 'generation-create')['body']
          as Map<String, dynamic>;
      expect(body['level'], 'ERROR');
      expect(body['statusMessage'], 'timeout');
    });

    test('error is excluded from metadata', () async {
      final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
      final span = ObservabilitySpan(
        name: 'test',
        kind: 'internal',
        attributes: {'error': 'bad', 'other': 'kept'},
      );
      span.end();
      sink.onSpan(span);

      await sink.flush();

      final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
      final batch = payload['batch'] as List<dynamic>;
      final body =
          _findByType(batch, 'span-create')['body'] as Map<String, dynamic>;
      final metadata = body['metadata'] as Map<String, dynamic>;
      expect(metadata.containsKey('error'), isFalse);
      expect(metadata['other'], 'kept');
    });
  });

  test('re-enqueues buffer on HTTP failure', () async {
    mockHttp.statusCode = 500;
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
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
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
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
    final sink = LangfuseSink(
      config: _configured(),
      httpClient: mockHttp,
      onError: errors.add,
    );
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(errors, hasLength(1));
    expect(errors.first, contains('langfuse export failed'));
    expect(errors.first, contains('500'));
  });

  test('calls onError callback on network exception', () async {
    mockHttp.shouldThrow = true;
    final errors = <String>[];
    final sink = LangfuseSink(
      config: _configured(),
      httpClient: mockHttp,
      onError: errors.add,
    );
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.flush();

    expect(errors, hasLength(1));
    expect(errors.first, contains('langfuse export error'));
  });

  test('does not write to stderr when onError is null', () async {
    mockHttp.shouldThrow = true;
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
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
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);
    final span = ObservabilitySpan(name: 'test', kind: 'internal');
    span.end();
    sink.onSpan(span);

    await sink.close();

    expect(mockHttp.requests, hasLength(1));
  });

  test('multiple spans batched in single request', () async {
    final sink = LangfuseSink(config: _configured(), httpClient: mockHttp);

    final span1 = ObservabilitySpan(name: 'span1', kind: 'tool');
    span1.end();
    sink.onSpan(span1);

    final span2 = ObservabilitySpan(name: 'span2', kind: 'llm');
    span2.end();
    sink.onSpan(span2);

    await sink.flush();

    expect(mockHttp.requests, hasLength(1));
    final payload = jsonDecode(mockHttp.bodies.first) as Map<String, dynamic>;
    final batch = payload['batch'] as List<dynamic>;
    // 2 unique traceIds = 2 trace-create + 2 observation events
    expect(batch, hasLength(4));

    final traceEvents = _allByType(batch, 'trace-create');
    expect(traceEvents, hasLength(2));

    final spanEvent = _findByType(batch, 'span-create');
    final genEvent = _findByType(batch, 'generation-create');
    expect(spanEvent['type'], 'span-create');
    expect(genEvent['type'], 'generation-create');
  });
}
