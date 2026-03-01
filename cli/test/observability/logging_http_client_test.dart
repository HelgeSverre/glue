import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/logging_http_client.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:test/test.dart';

class _MockSink extends ObservabilitySink {
  final List<ObservabilitySpan> spans = [];

  @override
  void onSpan(ObservabilitySpan span) => spans.add(span);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _MockHttpClient extends http.BaseClient {
  int statusCode = 200;
  bool shouldThrow = false;
  String errorMessage = 'connection failed';
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (shouldThrow) throw Exception(errorMessage);
    return http.StreamedResponse(
      Stream.value([]),
      statusCode,
    );
  }
}

void main() {
  late _MockSink sink;
  late Observability obs;
  late _MockHttpClient mockHttp;
  late LoggingHttpClient client;

  setUp(() {
    sink = _MockSink();
    obs = Observability(debugController: DebugController());
    obs.addSink(sink);
    mockHttp = _MockHttpClient();
    client = LoggingHttpClient(inner: mockHttp, obs: obs);
  });

  test('creates http span with method and URL attributes', () async {
    final request = http.Request('GET', Uri.parse('https://example.com/api'));

    await client.send(request);

    expect(sink.spans, hasLength(1));
    expect(sink.spans.first.name, 'http GET');
    expect(sink.spans.first.kind, 'http');
    expect(
      sink.spans.first.attributes['http.method'],
      'GET',
    );
    expect(
      sink.spans.first.attributes['http.url'],
      'https://example.com/api',
    );
  });

  test('records status_code on success', () async {
    mockHttp.statusCode = 201;
    final request = http.Request('POST', Uri.parse('https://example.com'));

    await client.send(request);

    expect(sink.spans.first.attributes['http.status_code'], 201);
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('records error on exception', () async {
    mockHttp.shouldThrow = true;
    final request = http.Request('GET', Uri.parse('https://example.com'));

    expect(
      () => client.send(request),
      throwsA(isA<Exception>()),
    );

    await Future<void>.delayed(Duration.zero);

    expect(sink.spans, hasLength(1));
    expect(
      sink.spans.first.attributes['error'],
      contains('connection failed'),
    );
    expect(sink.spans.first.endTime, isNotNull);
  });

  test('delegates to inner client', () async {
    final request = http.Request('PUT', Uri.parse('https://example.com/data'));

    await client.send(request);

    expect(mockHttp.lastRequest, isNotNull);
    expect(mockHttp.lastRequest!.method, 'PUT');
    expect(mockHttp.lastRequest!.url.toString(), 'https://example.com/data');
  });

  test('returns response from inner client', () async {
    mockHttp.statusCode = 204;
    final request = http.Request('DELETE', Uri.parse('https://example.com/1'));

    final response = await client.send(request);

    expect(response.statusCode, 204);
  });
}
