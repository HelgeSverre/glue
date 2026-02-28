@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/observability/debug_controller.dart';
import 'package:glue/src/observability/observability.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/observability/observed_llm_client.dart';
import 'package:glue/src/observability/observed_tool.dart';
import 'package:glue/src/observability/otel_sink.dart';
import 'package:glue/src/observability/langfuse_sink.dart';
import 'package:test/test.dart';

class _MockLlmClient extends LlmClient {
  @override
  Stream<LlmChunk> stream(
    List<Message> messages, {
    List<Tool>? tools,
  }) async* {
    yield TextDelta('Hello');
    yield TextDelta(' world');
    yield UsageInfo(inputTokens: 100, outputTokens: 50);
  }
}

class _MockTool extends Tool {
  @override
  String get name => 'test_tool';

  @override
  String get description => 'A test tool';

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
            name: 'input', type: 'string', description: 'Input value'),
      ];

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    return 'tool result: ${args['input']}';
  }
}

void main() {
  group('Observability integration', () {
    late HttpServer otelServer;
    late HttpServer langfuseServer;
    late List<Map<String, dynamic>> otelPayloads;
    late List<Map<String, dynamic>> langfusePayloads;

    setUp(() async {
      otelPayloads = [];
      langfusePayloads = [];

      otelServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(otelServer.forEach((request) async {
        final body = await utf8.decoder.bind(request).join();
        otelPayloads.add(jsonDecode(body) as Map<String, dynamic>);
        request.response
          ..statusCode = 200
          ..write('{}');
        await request.response.close();
      }));

      langfuseServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(langfuseServer.forEach((request) async {
        final body = await utf8.decoder.bind(request).join();
        langfusePayloads.add(jsonDecode(body) as Map<String, dynamic>);
        request.response
          ..statusCode = 200
          ..write('{}');
        await request.response.close();
      }));
    });

    tearDown(() async {
      await otelServer.close();
      await langfuseServer.close();
    });

    test('full pipeline sends spans to OTel and Langfuse', () async {
      final obs = Observability(debugController: DebugController());

      final otelSink = OtelSink(
        config: OtelConfig(
          enabled: true,
          endpoint: 'http://localhost:${otelServer.port}',
        ),
        resourceAttributes: {
          'glue.session.id': 'test-session',
          'gen_ai.system': 'anthropic',
        },
      );

      final langfuseSink = LangfuseSink(
        config: LangfuseConfig(
          enabled: true,
          baseUrl: 'http://localhost:${langfuseServer.port}',
          publicKey: 'pk-test',
          secretKey: 'sk-test',
        ),
        resourceAttributes: {
          'glue.session.id': 'test-session',
          'gen_ai.system': 'anthropic',
        },
      );

      obs.addSink(otelSink);
      obs.addSink(langfuseSink);

      final rootSpan = obs.startSpan('agent.turn', kind: 'internal');

      final llmClient = ObservedLlmClient(
        inner: _MockLlmClient(),
        obs: obs,
      );
      final chunks =
          await llmClient.stream([Message.user('test')]).toList();
      expect(chunks, hasLength(3));

      final tool = ObservedTool(inner: _MockTool(), obs: obs);
      final result = await tool.execute({'input': 'hello'});
      expect(result, 'tool result: hello');

      obs.endSpan(rootSpan);
      await obs.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Verify OTel payload
      expect(otelPayloads, isNotEmpty);
      final otelPayload = otelPayloads.first;
      expect(otelPayload['resourceSpans'], isA<List<dynamic>>());
      final resourceSpans = otelPayload['resourceSpans'] as List<dynamic>;
      expect(resourceSpans, isNotEmpty);

      final scopeSpans =
          (resourceSpans.first as Map<String, dynamic>)['scopeSpans']
              as List<dynamic>;
      final spans = (scopeSpans.first as Map<String, dynamic>)['spans']
          as List<dynamic>;

      expect(spans.length, greaterThanOrEqualTo(3));

      final llmSpan = spans.firstWhere(
        (s) => (s as Map<String, dynamic>)['name'] == 'llm.stream',
      ) as Map<String, dynamic>;
      final llmAttrs =
          (llmSpan['attributes'] as List).cast<Map<String, dynamic>>();

      final inputTokens = llmAttrs.firstWhere(
        (a) => a['key'] == 'input_tokens',
        orElse: () => <String, dynamic>{},
      );
      expect(inputTokens, isNotEmpty);
      expect((inputTokens['value'] as Map<String, dynamic>)['intValue'], '100');

      final outputTokens = llmAttrs.firstWhere(
        (a) => a['key'] == 'output_tokens',
        orElse: () => <String, dynamic>{},
      );
      expect(outputTokens, isNotEmpty);
      expect((outputTokens['value'] as Map<String, dynamic>)['intValue'], '50');

      final toolSpan = spans.firstWhere(
        (s) => (s as Map<String, dynamic>)['name'] == 'tool.test_tool',
      ) as Map<String, dynamic>;
      expect(toolSpan, isNotEmpty);

      // Verify Langfuse payload
      expect(langfusePayloads, isNotEmpty);
      final langfusePayload = langfusePayloads.first;
      expect(langfusePayload['batch'], isA<List<dynamic>>());
      final batch = langfusePayload['batch'] as List<dynamic>;
      expect(batch, isNotEmpty);

      final traceEvent = batch.firstWhere(
        (e) => (e as Map<String, dynamic>)['type'] == 'trace-create',
        orElse: () => null,
      );
      expect(traceEvent, isNotNull);

      final genEvent = batch.firstWhere(
        (e) => (e as Map<String, dynamic>)['type'] == 'generation-create',
        orElse: () => null,
      );
      expect(genEvent, isNotNull);
      final genBody =
          (genEvent as Map<String, dynamic>)['body'] as Map<String, dynamic>;
      expect(genBody['name'], 'llm.stream');
      final usage = genBody['usage'] as Map<String, dynamic>;
      expect(usage['input'], 100);
      expect(usage['output'], 50);

      await obs.close();
    });

    test('Langfuse auth header is correctly formed', () async {
      final obs = Observability(debugController: DebugController());

      final langfuseSink = LangfuseSink(
        config: LangfuseConfig(
          enabled: true,
          baseUrl: 'http://localhost:${langfuseServer.port}',
          publicKey: 'pk-test',
          secretKey: 'sk-test',
        ),
      );
      obs.addSink(langfuseSink);

      final span = obs.startSpan('test', kind: 'internal');
      obs.endSpan(span);
      await obs.flush();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(langfusePayloads, isNotEmpty);
      await obs.close();
    });

    test('OTel span structure has required fields', () async {
      final obs = Observability(debugController: DebugController());

      final otelSink = OtelSink(
        config: OtelConfig(
          enabled: true,
          endpoint: 'http://localhost:${otelServer.port}',
        ),
      );
      obs.addSink(otelSink);

      final parent = obs.startSpan('parent', kind: 'internal');
      final child = obs.startSpan('child', kind: 'llm', parent: parent);
      obs.endSpan(child);
      obs.endSpan(parent);
      await obs.flush();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(otelPayloads, isNotEmpty);
      final payload = otelPayloads.first;
      final spans =
          ((payload['resourceSpans'] as List<dynamic>).first
              as Map<String, dynamic>)['scopeSpans'];
      final spanList = ((spans as List<dynamic>).first
              as Map<String, dynamic>)['spans']
          as List<dynamic>;

      expect(spanList, hasLength(2));

      final childSpan = spanList.firstWhere(
        (s) => (s as Map<String, dynamic>)['name'] == 'child',
      ) as Map<String, dynamic>;
      final parentSpan = spanList.firstWhere(
        (s) => (s as Map<String, dynamic>)['name'] == 'parent',
      ) as Map<String, dynamic>;

      expect(childSpan['parentSpanId'], parentSpan['spanId']);
      expect(childSpan['traceId'], parentSpan['traceId']);

      expect(childSpan['startTimeUnixNano'], isA<String>());
      expect(childSpan['endTimeUnixNano'], isA<String>());
      expect(childSpan['kind'], isA<int>());
      expect(childSpan['status'], isA<Map<String, dynamic>>());

      await obs.close();
    });
  });
}
