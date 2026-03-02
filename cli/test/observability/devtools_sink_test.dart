import 'package:glue/src/observability/devtools_sink.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:test/test.dart';

void main() {
  late DevToolsSink sink;

  setUp(() {
    sink = DevToolsSink();
  });

  ObservabilitySpan makeSpan(String name, String kind,
      {Map<String, dynamic>? attributes}) {
    final span = ObservabilitySpan(
      name: name,
      kind: kind,
      attributes: attributes,
    );
    span.end();
    return span;
  }

  test('onSpan does not throw for llm span', () {
    final span = makeSpan('llm.stream', 'llm', attributes: {
      'gen_ai.system': 'anthropic',
      'gen_ai.request.model': 'claude-sonnet-4-20250514',
      'input_tokens': 100,
      'output_tokens': 50,
      'llm.ttfb_ms': 42,
    });
    expect(() => sink.onSpan(span), returnsNormally);
  });

  test('onSpan does not throw for tool span', () {
    final span = makeSpan('tool.read_file', 'tool', attributes: {
      'tool.name': 'read_file',
      'tool.result_length': 1234,
    });
    expect(() => sink.onSpan(span), returnsNormally);
  });

  test('onSpan does not throw for http span', () {
    final span = makeSpan('http.request', 'http', attributes: {
      'http.method': 'POST',
      'http.url': 'https://api.anthropic.com/v1/messages',
      'http.status_code': 200,
    });
    expect(() => sink.onSpan(span), returnsNormally);
  });

  test('onSpan does not throw for span with error', () {
    final span = makeSpan('tool.bash', 'tool', attributes: {
      'tool.name': 'bash',
      'error': 'command not found',
    });
    expect(() => sink.onSpan(span), returnsNormally);
  });

  test('onSpan does not throw for span with missing attributes', () {
    final span = makeSpan('llm.stream', 'llm');
    expect(() => sink.onSpan(span), returnsNormally);
  });

  test('onSpan does not throw for unknown span kind', () {
    final span = makeSpan('custom.operation', 'custom');
    expect(() => sink.onSpan(span), returnsNormally);
  });

  test('flush completes immediately', () async {
    await expectLater(sink.flush(), completes);
  });

  test('close completes immediately', () async {
    await expectLater(sink.close(), completes);
  });
}
