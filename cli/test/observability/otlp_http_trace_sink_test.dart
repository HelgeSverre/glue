import 'dart:convert';
import 'dart:typed_data';

import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/observability/otlp_http_trace_sink.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  Object? lastBody;
  Map<String, String>? lastHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    lastHeaders = request.headers;
    if (request is http.Request) {
      lastBody =
          request.bodyBytes.isNotEmpty ? request.bodyBytes : request.body;
    }
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

void main() {
  test('normalizes base endpoint to OTLP traces endpoint', () {
    final normalized = normalizeOtlpTracesEndpoint(
      'https://app.phoenix.arize.com/s/helge-sverre',
    );
    expect(
      normalized.toString(),
      'https://app.phoenix.arize.com/s/helge-sverre/v1/traces',
    );
  });

  test('exports spans as OTLP JSON with headers and resource attrs', () async {
    final client = _FakeClient();
    final sink = OtlpHttpTraceSink(
      config: const OtelConfig(
        enabled: true,
        endpoint: 'https://collector.example.test',
        protocol: OtelProtocol.httpJson,
        headers: {'Authorization': 'Bearer secret'},
        serviceName: 'glue-test',
        resourceAttributes: {'openinference.project.name': 'test-project'},
      ),
      client: client,
    );

    final parent = ObservabilitySpan(
      name: 'agent.turn',
      kind: 'agent',
      attributes: {'openinference.span.kind': 'AGENT'},
    );
    parent.addEvent('agent.started');
    parent.end(extra: {'ok': true});
    sink.onSpan(parent);

    final child = ObservabilitySpan(
      name: 'llm.stream',
      kind: 'llm',
      traceId: parent.traceId,
      parentSpanId: parent.spanId,
      attributes: {
        'openinference.span.kind': 'LLM',
        'llm.token_count.total': 10,
      },
    );
    child.end();
    sink.onSpan(child);

    await sink.flush();

    expect(client.lastRequest?.url.toString(),
        'https://collector.example.test/v1/traces');
    expect(client.lastHeaders?['Authorization'], 'Bearer secret');
    expect(client.lastHeaders?['Content-Type'], 'application/json');

    final jsonBody = client.lastBody is Uint8List
        ? utf8.decode(client.lastBody as Uint8List)
        : client.lastBody as String;
    final decoded = (jsonDecode(jsonBody) as Map).cast<String, dynamic>();
    final resourceSpans = decoded['resourceSpans'] as List;
    final firstResourceSpan =
        (resourceSpans.single as Map).cast<String, dynamic>();
    final resource =
        (firstResourceSpan['resource'] as Map).cast<String, dynamic>();
    final resourceAttrs = resource['attributes'] as List;
    expect(jsonEncode(resourceAttrs), contains('glue-test'));
    expect(jsonEncode(resourceAttrs), contains('test-project'));

    final scopeSpans = firstResourceSpan['scopeSpans'] as List;
    final firstScopeSpan = (scopeSpans.single as Map).cast<String, dynamic>();
    final spans = firstScopeSpan['spans'] as List;
    final firstSpan = (spans.first as Map).cast<String, dynamic>();
    final secondSpan = (spans[1] as Map).cast<String, dynamic>();
    expect(spans, hasLength(2));
    expect(firstSpan['traceId'], parent.traceId);
    expect(secondSpan['parentSpanId'], parent.spanId);
    expect(jsonEncode(firstSpan), contains('agent.started'));

    await sink.close();
  });

  test('exports spans as OTLP protobuf when configured', () async {
    final client = _FakeClient();
    final sink = OtlpHttpTraceSink(
      config: const OtelConfig(
        enabled: true,
        endpoint: 'https://collector.example.test',
        protocol: OtelProtocol.httpProtobuf,
        headers: {'Authorization': 'Bearer secret'},
        serviceName: 'glue-test',
      ),
      client: client,
    );

    final span = ObservabilitySpan(
      name: 'agent.turn',
      kind: 'agent',
      attributes: {'openinference.span.kind': 'AGENT'},
    );
    span.end(extra: {'ok': true});
    sink.onSpan(span);

    await sink.flush();

    expect(client.lastRequest?.url.toString(),
        'https://collector.example.test/v1/traces');
    expect(client.lastHeaders?['Authorization'], 'Bearer secret');
    expect(client.lastHeaders?['Content-Type'], 'application/x-protobuf');
    expect(client.lastBody, isA<Uint8List>());
    expect((client.lastBody as Uint8List).isNotEmpty, isTrue);

    await sink.close();
  });
}
