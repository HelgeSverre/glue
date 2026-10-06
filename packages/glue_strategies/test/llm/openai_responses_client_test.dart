import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue_core/glue_core.dart';
import 'package:http/http.dart' as http;
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

void main() {
  test('failed response preserves provider diagnostics and usage', () async {
    final chunks = <LlmChunk>[];
    final stream = OpenAiResponsesClient.parseStreamEvents(
      Stream.fromIterable([
        {
          'type': 'response.failed',
          'response': {
            'error': {'code': 'server_error', 'message': 'Please try again'},
            'usage': {
              'input_tokens': 100,
              'input_tokens_details': {'cached_tokens': 80},
              'output_tokens': 25,
              'output_tokens_details': {'reasoning_tokens': 10},
            },
          },
        },
      ]),
    );
    await expectLater(
      stream.map((chunk) {
        chunks.add(chunk);
        return chunk;
      }),
      emitsInOrder([
        isA<UsageInfo>(),
        emitsError(
          predicate<Object>(
            (error) =>
                error.toString().contains('server_error') &&
                error.toString().contains('Please try again'),
          ),
        ),
        emitsDone,
      ]),
    );
    final usage = chunks.whereType<UsageInfo>().single;
    expect(usage.inputTokens, 20);
    expect(usage.cacheReadTokens, 80);
    expect(usage.outputTokens, 25);
    expect(usage.reasoningTokens, 10);
  });

  for (final event in [
    {
      'type': 'response.incomplete',
      'response': {
        'incomplete_details': {'reason': 'max_output_tokens'},
        'usage': {'input_tokens': 12, 'output_tokens': 4},
      },
    },
    {'type': 'error', 'code': 'invalid_prompt', 'message': 'Prompt rejected'},
  ]) {
    test('${event['type']} surfaces diagnostics', () async {
      await expectLater(
        OpenAiResponsesClient.parseStreamEvents(Stream.value(event)),
        emitsInOrder([
          if (event['type'] == 'response.incomplete')
            isA<UsageInfo>()
                .having((usage) => usage.inputTokens, 'input', 12)
                .having((usage) => usage.outputTokens, 'output', 4)
                .having((usage) => usage.cacheReadTokens, 'cache', 0)
                .having((usage) => usage.reasoningTokens, 'reasoning', isNull),
          emitsError(
            predicate<Object>((error) {
              final message = error.toString();
              return event['type'] == 'response.incomplete'
                  ? message.contains('max_output_tokens')
                  : message.contains('invalid_prompt') &&
                        message.contains('Prompt rejected');
            }),
          ),
          emitsDone,
        ]),
      );
    });
  }

  for (final events in <List<Map<String, dynamic>>>[
    [],
    [
      {'type': 'response.created'},
      {'type': 'unknown.event'},
    ],
    [
      {'type': 'response.output_text.delta', 'delta': 'partial'},
    ],
  ]) {
    test('EOF without completion is an error: $events', () async {
      await expectLater(
        OpenAiResponsesClient.parseStreamEvents(Stream.fromIterable(events)),
        emitsInOrder([
          if (events.any((event) => event['delta'] != null)) isA<TextDelta>(),
          emitsError(
            predicate<Object>(
              (error) => error.toString().contains('response.completed'),
            ),
          ),
          emitsDone,
        ]),
      );
    });
  }

  for (final type in ['response.failed', 'response.incomplete', 'error']) {
    for (final response in [
      null,
      <String, dynamic>{},
      {'usage': null},
    ]) {
      test('$type has fallback diagnostics with $response', () async {
        await expectLater(
          OpenAiResponsesClient.parseStreamEvents(
            Stream.value({'type': type, 'response': response}),
          ),
          emitsInOrder([
            emitsError(
              predicate<Object>(
                (error) =>
                    error.toString().contains(type) &&
                    error.toString().contains('without'),
              ),
            ),
            emitsDone,
          ]),
        );
      });
    }
  }

  for (final response in [
    null,
    <String, dynamic>{},
    {'usage': null},
  ]) {
    test('completion without usage is valid: $response', () async {
      final chunks = await OpenAiResponsesClient.parseStreamEvents(
        Stream.fromIterable([
          {'type': 'response.created'},
          {'type': 'unknown.event'},
          {'type': 'response.completed', 'response': response},
          {'type': 'response.output_text.delta', 'delta': 'ignored'},
        ]),
      ).toList();
      expect(chunks, isEmpty);
    });
  }

  group('HTTP/SSE transport boundary', () {
    for (final type in [
      'response.completed',
      'response.failed',
      'response.incomplete',
      'error',
    ]) {
      for (final withText in [false, true]) {
        test('$type closes an open body, no replay (text=$withText)', () async {
          var cancelled = false;
          final body = StreamController<List<int>>(
            onCancel: () => cancelled = true,
          );
          addTearDown(body.close);
          final transport = _StreamingClient(body.stream);
          var attempts = 0;
          final client = _responsesClient(() {
            attempts++;
            return transport;
          });
          if (withText) {
            body.add(
              _sse({'type': 'response.output_text.delta', 'delta': 'once'}),
            );
          }
          body.add(
            _sse({
              'type': type,
              'code': 'server_error',
              'message': 'API error 503: provider failure',
              'response': {
                'error': {
                  'code': 'server_error',
                  'message': 'API error 503: provider failure',
                },
                'incomplete_details': {'reason': 'max_output_tokens'},
                'usage': {'input_tokens': 5, 'output_tokens': 2},
              },
            }),
          );
          // Leave the HTTP body open: the terminal event must cancel it.
          await expectLater(
            client.stream(const []),
            emitsInOrder([
              if (withText)
                isA<TextDelta>().having((chunk) => chunk.text, 'text', 'once'),
              if (type != 'error') isA<UsageInfo>(),
              if (type != 'response.completed')
                emitsError(
                  predicate<Object>((error) => error.toString().contains(type)),
                ),
              emitsDone,
            ]),
          );
          expect(attempts, 1);
          expect(transport.closes, 1);
          expect(cancelled, isTrue);
        });
      }
    }

    for (final payload in [
      '',
      'data: [DONE]\n\n',
      'data: {"type":"response.output_text.delta","delta":"once"}\n\ndata: [DONE]\n\n',
    ]) {
      test('EOF/[DONE] without completion is rejected: $payload', () async {
        final transport = _StreamingClient(Stream.value(utf8.encode(payload)));
        var attempts = 0;
        final client = _responsesClient(() {
          attempts++;
          return transport;
        });
        await expectLater(
          client.stream(const []),
          emitsInOrder([
            if (payload.contains('delta')) isA<TextDelta>(),
            emitsError(
              predicate<Object>(
                (error) => error.toString().contains('response.completed'),
              ),
            ),
            emitsDone,
          ]),
        );
        expect(attempts, 1);
        expect(transport.closes, 1);
      });
    }

    test('provider failure without usage is fail-fast before output', () async {
      final transport = _StreamingClient(
        Stream.value(
          _sse({
            'type': 'response.failed',
            'response': {
              'error': {
                'code': 'server_error',
                'message': 'API error 503: failed',
              },
            },
          }),
        ),
      );
      var attempts = 0;
      final client = _responsesClient(() {
        attempts++;
        return transport;
      });
      await expectLater(
        client.stream(const []),
        emitsInOrder([
          emitsError(
            predicate<Object>(
              (error) => error.toString().contains('server_error'),
            ),
          ),
          emitsDone,
        ]),
      );
      expect(attempts, 1);
      expect(transport.closes, 1);
    });

    test('transient transport failure after text does not replay', () async {
      Stream<List<int>> bytes() async* {
        yield _sse({'type': 'response.output_text.delta', 'delta': 'once'});
        throw const SocketException('connection lost');
      }

      final transport = _StreamingClient(bytes());
      var attempts = 0;
      final client = _responsesClient(() {
        attempts++;
        return transport;
      });
      await expectLater(
        client.stream(const []),
        emitsInOrder([
          isA<TextDelta>(),
          emitsError(isA<SocketException>()),
          emitsDone,
        ]),
      );
      expect(attempts, 1);
      expect(transport.closes, 1);
    });

    test('caller cancellation closes HTTP body without EOF error', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);
      final transport = _StreamingClient(body.stream);
      body.add(_sse({'type': 'response.output_text.delta', 'delta': 'once'}));
      final chunks = await _responsesClient(
        () => transport,
      ).stream(const []).take(1).toList();
      expect(chunks, hasLength(1));
      expect(transport.closes, 1);
      expect(cancelled, isTrue);
    });
  });

  test(
    'parses reasoning summary, function call, artifact, and usage',
    () async {
      final events = Stream<Map<String, dynamic>>.fromIterable([
        {'type': 'response.reasoning_summary_text.delta', 'delta': 'Checking'},
        {
          'type': 'response.output_item.added',
          'item': {
            'type': 'function_call',
            'call_id': 'call_1',
            'name': 'read_file',
          },
        },
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'reasoning',
            'id': 'rs_1',
            'encrypted_content': 'opaque',
          },
        },
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'call_id': 'call_1',
            'name': 'read_file',
            'arguments': '{"path":"a.txt"}',
          },
        },
        {
          'type': 'response.completed',
          'response': {
            'usage': {
              'input_tokens': 100,
              'input_tokens_details': {'cached_tokens': 80},
              'output_tokens': 25,
              'output_tokens_details': {'reasoning_tokens': 10},
            },
          },
        },
      ]);

      final chunks = await OpenAiResponsesClient.parseStreamEvents(
        events,
      ).toList();
      expect(chunks.whereType<ThinkingDelta>().single.text, 'Checking');
      expect(chunks.whereType<ToolCallComplete>().single.toolCall.arguments, {
        'path': 'a.txt',
      });
      expect(chunks.whereType<ReasoningArtifactChunk>(), hasLength(1));
      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 20);
      expect(usage.cacheReadTokens, 80);
      expect(usage.reasoningTokens, 10);
    },
  );
}

List<int> _sse(Map<String, dynamic> event) =>
    utf8.encode('data: ${jsonEncode(event)}\n\n');

OpenAiResponsesClient _responsesClient(http.Client Function() factory) =>
    OpenAiResponsesClient(
      apiKey: 'test',
      model: 'test',
      systemPrompt: '',
      baseUrl: 'https://example.test/v1',
      requestClientFactory: factory,
    );

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.bytes);

  final Stream<List<int>> bytes;
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/responses');
    return http.StreamedResponse(bytes, 200);
  }

  @override
  void close() => closes++;
}
