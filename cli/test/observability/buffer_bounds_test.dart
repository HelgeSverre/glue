import 'dart:convert';

import 'package:glue/src/observability/langfuse_sink.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/observability/otel_sink.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock HTTP client with configurable status code
// ---------------------------------------------------------------------------

class _MockHttpClient extends http.BaseClient {
  int statusCode;
  final List<http.BaseRequest> requests = [];

  _MockHttpClient({this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"status":"ok"}')),
      statusCode,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ObservabilitySpan _span(String name) => ObservabilitySpan(
      name: name,
      kind: 'internal',
    )..end();

void main() {
  group('OtelSink buffer bounds', () {
    late _MockHttpClient mockClient;
    late OtelSink sink;

    setUp(() {
      mockClient = _MockHttpClient(statusCode: 500);
      sink = OtelSink(
        config: const OtelConfig(
          enabled: true,
          endpoint: 'http://localhost:4318/v1/traces',
        ),
        httpClient: mockClient,
        maxBufferSize: 1000,
      );
    });

    test('buffer does not exceed maxBufferSize', () async {
      for (var i = 0; i < 1500; i++) {
        sink.onSpan(_span('span-$i'));
      }

      await sink.flush();

      // After flush fails and re-enqueues, buffer should be capped at 1000.
      // We add 0 more spans, so the buffer should be exactly 1000.
      // Add one more span to observe the buffer size via a second flush.
      mockClient.statusCode = 200;
      await sink.flush();
      // The successful flush should have sent exactly 1000 spans.
      // Last request should contain 1000 spans.
      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final resourceSpans = payload['resourceSpans'] as List;
      final scopeSpans = (resourceSpans[0] as Map)['scopeSpans'] as List;
      final spans = (scopeSpans[0] as Map)['spans'] as List;
      expect(spans.length, 1000);
    });

    test('buffer preserves newest spans on overflow', () async {
      for (var i = 0; i < 1500; i++) {
        sink.onSpan(_span('span-$i'));
      }

      // Buffer should have dropped oldest (0..499), kept 500..1499
      // Flush with success to inspect what was sent.
      mockClient.statusCode = 200;
      await sink.flush();

      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final resourceSpans = payload['resourceSpans'] as List;
      final scopeSpans = (resourceSpans[0] as Map)['scopeSpans'] as List;
      final spans = (scopeSpans[0] as Map)['spans'] as List;
      // First span in the flushed batch should be span-500 (oldest kept).
      expect((spans.first as Map)['name'], 'span-500');
      // Last span should be span-1499 (newest).
      expect((spans.last as Map)['name'], 'span-1499');
    });

    test('normal operation unaffected below limit', () async {
      mockClient.statusCode = 200;
      for (var i = 0; i < 50; i++) {
        sink.onSpan(_span('span-$i'));
      }
      await sink.flush();

      expect(mockClient.requests.length, 1);
      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final resourceSpans = payload['resourceSpans'] as List;
      final scopeSpans = (resourceSpans[0] as Map)['scopeSpans'] as List;
      final spans = (scopeSpans[0] as Map)['spans'] as List;
      expect(spans.length, 50);
    });

    test('re-enqueue plus new spans respects limit', () async {
      // Fill buffer with 800 spans, flush fails -> re-enqueued.
      for (var i = 0; i < 800; i++) {
        sink.onSpan(_span('old-$i'));
      }
      await sink.flush();
      // Now buffer has 800 re-enqueued spans.

      // Add 400 more -> total 1200, should be trimmed to 1000.
      for (var i = 0; i < 400; i++) {
        sink.onSpan(_span('new-$i'));
      }

      // Flush successfully to inspect.
      mockClient.statusCode = 200;
      await sink.flush();

      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final resourceSpans = payload['resourceSpans'] as List;
      final scopeSpans = (resourceSpans[0] as Map)['scopeSpans'] as List;
      final spans = (scopeSpans[0] as Map)['spans'] as List;
      expect(spans.length, 1000);
      // Oldest 200 old-spans should have been dropped.
      expect((spans.first as Map)['name'], 'old-200');
      // All 400 new spans should be present at the end.
      expect((spans.last as Map)['name'], 'new-399');
    });
  });

  group('LangfuseSink buffer bounds', () {
    late _MockHttpClient mockClient;
    late LangfuseSink sink;

    setUp(() {
      mockClient = _MockHttpClient(statusCode: 500);
      sink = LangfuseSink(
        config: const LangfuseConfig(
          enabled: true,
          baseUrl: 'http://localhost:3000',
          publicKey: 'pk',
          secretKey: 'sk',
        ),
        httpClient: mockClient,
        maxBufferSize: 1000,
      );
    });

    test('buffer does not exceed maxBufferSize', () async {
      for (var i = 0; i < 1500; i++) {
        sink.onSpan(_span('span-$i'));
      }

      await sink.flush();

      mockClient.statusCode = 200;
      await sink.flush();

      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final batch = payload['batch'] as List;
      // Each internal span produces 1 event in Langfuse.
      expect(batch.length, 1000);
    });

    test('buffer preserves newest spans on overflow', () async {
      for (var i = 0; i < 1500; i++) {
        sink.onSpan(_span('span-$i'));
      }

      mockClient.statusCode = 200;
      await sink.flush();

      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final batch = payload['batch'] as List;
      // First event body should be span-500 (oldest kept).
      final firstEvent = batch.first as Map<String, dynamic>;
      final lastEvent = batch.last as Map<String, dynamic>;
      expect((firstEvent['body'] as Map<String, dynamic>)['name'], 'span-500');
      // Last event body should be span-1499 (newest).
      expect((lastEvent['body'] as Map<String, dynamic>)['name'], 'span-1499');
    });

    test('normal operation unaffected below limit', () async {
      mockClient.statusCode = 200;
      for (var i = 0; i < 50; i++) {
        sink.onSpan(_span('span-$i'));
      }
      await sink.flush();

      expect(mockClient.requests.length, 1);
      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final batch = payload['batch'] as List;
      // Each span produces trace-create + span-create = 100 events for 50 spans.
      final spanEvents = batch
          .cast<Map<String, dynamic>>()
          .where((e) => e['type'] == 'span-create')
          .toList();
      expect(spanEvents.length, 50);
    });

    test('re-enqueue plus new spans respects limit', () async {
      for (var i = 0; i < 800; i++) {
        sink.onSpan(_span('old-$i'));
      }
      await sink.flush();

      for (var i = 0; i < 400; i++) {
        sink.onSpan(_span('new-$i'));
      }

      mockClient.statusCode = 200;
      await sink.flush();

      final lastRequest = mockClient.requests.last as http.Request;
      final payload = jsonDecode(lastRequest.body) as Map<String, dynamic>;
      final batch = payload['batch'] as List;
      // 1000 spans in buffer, each produces trace-create + span-create.
      final spanEvents = batch
          .cast<Map<String, dynamic>>()
          .where((e) => e['type'] == 'span-create')
          .toList();
      expect(spanEvents.length, 1000);
      expect((spanEvents.first['body'] as Map<String, dynamic>)['name'],
          'old-200');
      expect(
          (spanEvents.last['body'] as Map<String, dynamic>)['name'], 'new-399');
    });
  });
}
