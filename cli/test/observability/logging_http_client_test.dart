import 'dart:convert';

import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/logging_http_client.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _RecordingSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];
  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
  @override
  void close() {}
}

http.StreamedResponse _ok(String body,
    {int status = 200, Map<String, String>? headers}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: headers ?? {'content-type': 'application/json'},
  );
}

void main() {
  late Observability obs;
  late _RecordingSink sink;

  setUp(() {
    obs = Observability(debugController: DebugController(enabled: true));
    sink = _RecordingSink();
    obs.addSink(sink);
  });

  test('emits one span per request with method + redacted url + headers',
      () async {
    final client = LoggingHttpClient(
      inner: _FakeClient((_) async => _ok('{"ok":true}')),
      observability: obs,
      spanKind: 'search.test',
    );

    final response = await client.get(
      Uri.parse('https://example.com/x?api_key=secret&q=cats'),
      headers: {'x-api-key': 'sk-xxx', 'Accept': 'application/json'},
    );
    expect(response.statusCode, 200);

    expect(sink.spans, hasLength(1));
    final span = sink.spans.single;
    expect(span.kind, 'http.search.test');
    expect(span.attributes['http.method'], 'GET');
    expect(span.attributes['http.url'], contains('api_key=****'));
    expect(span.attributes['http.url'], contains('q=cats'));
    final headers = span.attributes['http.request_headers'] as Map;
    expect(headers['x-api-key'], '****');
    expect(headers['Accept'], 'application/json');
    expect(span.attributes['http.status_code'], 200);
    expect(span.attributes['http.response_body'], '{"ok":true}');
  });

  test('masks request body secrets', () async {
    final client = LoggingHttpClient(
      inner: _FakeClient((_) async => _ok('{}')),
      observability: obs,
      spanKind: 'llm.test',
    );

    await client.post(
      Uri.parse('https://example.com/v1/chat'),
      headers: {'content-type': 'application/json'},
      body: '{"api_key":"sk-abc123","model":"gpt-4"}',
    );

    final span = sink.spans.single;
    final body = span.attributes['http.request_body'] as String;
    expect(body, contains('"api_key":"****"'));
    expect(body, contains('"model":"gpt-4"'));
  });

  test('forwards response bytes unchanged to caller', () async {
    const payload = '{"hello":"world"}';
    final client = LoggingHttpClient(
      inner: _FakeClient((_) async => _ok(payload)),
      observability: obs,
      spanKind: 'fetch.test',
    );

    final response = await client.get(Uri.parse('https://example.com/'));
    expect(response.body, payload);
  });

  test('captures transport errors as error spans and rethrows', () async {
    final client = LoggingHttpClient(
      inner: _FakeClient((_) async {
        throw Exception('connection reset');
      }),
      observability: obs,
      spanKind: 'search.test',
    );

    await expectLater(
      client.get(Uri.parse('https://example.com/')),
      throwsA(isA<Exception>()),
    );

    expect(sink.spans, hasLength(1));
    final span = sink.spans.single;
    expect(span.attributes['error'], true);
    expect(span.attributes['error.type'], '_Exception');
    expect(span.attributes['error.message'], contains('connection reset'));
  });

  test('ends span when streaming response stream errors', () async {
    final client = LoggingHttpClient(
      inner: _FakeClient((_) async => http.StreamedResponse(
            Stream<List<int>>.error(Exception('stream fail')),
            200,
            headers: {},
          )),
      observability: obs,
      spanKind: 'llm.test',
    );

    await expectLater(
      client.get(Uri.parse('https://example.com/')),
      throwsA(isA<Exception>()),
    );

    expect(sink.spans, hasLength(1));
    final span = sink.spans.single;
    expect(span.attributes['error'], true);
    expect(span.attributes['http.status_code'], 200);
  });

  test('inherits parent trace id from active span', () async {
    final root = obs.startSpan('agent.turn');
    obs.activeSpan = root;

    final client = LoggingHttpClient(
      inner: _FakeClient((_) async => _ok('{}')),
      observability: obs,
      spanKind: 'llm.anthropic',
    );

    await client.get(Uri.parse('https://api.anthropic.com/v1/messages'));

    final httpSpan =
        sink.spans.firstWhere((s) => s.name == 'http.llm.anthropic');
    expect(httpSpan.traceId, root.traceId);
    expect(httpSpan.parentSpanId, root.spanId);
  });

  test('honors maxBodyBytes cap', () async {
    final big = 'X' * 1000;
    final client = LoggingHttpClient(
      inner: _FakeClient((_) async => _ok(big)),
      observability: obs,
      spanKind: 'fetch.test',
      maxBodyBytes: 100,
    );

    await client.get(Uri.parse('https://example.com/'));
    final span = sink.spans.single;
    final logged = span.attributes['http.response_body'] as String;
    expect(logged, contains('truncated'));
    expect(logged.length, lessThan(big.length));
    // Raw byte count should reflect full body, not the truncated log.
    expect(span.attributes['http.response_body_size'], 1000);
  });
}
