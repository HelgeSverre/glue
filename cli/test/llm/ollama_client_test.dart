import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _rawResponse(int status, String body) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('OllamaClient.parseStream', () {
    test('parses text deltas from streaming JSON', () async {
      final events = [
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': 'Hello '},
          'done': false,
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': 'world'},
          'done': false,
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 26,
          'eval_count': 10,
        },
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final text = chunks.whereType<TextDelta>().map((d) => d.text).join();
      expect(text, 'Hello world');

      final usage = chunks.whereType<UsageInfo>().toList();
      expect(usage, hasLength(1));
      expect(usage.first.inputTokens, 26);
      expect(usage.first.outputTokens, 10);
    });

    test('parses tool calls', () async {
      final events = [
        {
          'model': 'llama3.2',
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'main.dart'},
                },
              },
            ],
          },
          'done': false,
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 20,
          'eval_count': 15,
        },
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.first.name, 'read_file');

      final toolCalls = chunks.whereType<ToolCallComplete>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');

      final startIdx = chunks.indexWhere((c) => c is ToolCallStart);
      final deltaIdx = chunks.indexWhere((c) => c is ToolCallComplete);
      expect(startIdx, lessThan(deltaIdx));
    });
  });

  group('Ollama message mapping', () {
    test('tool result uses tool name not call ID', () {
      final msg = Message.toolResult(
        callId: const ToolCallId('ollama_tc_1'),
        content: 'file contents',
        toolName: 'read_file',
      );
      expect(msg.toolName, 'read_file');
      expect(msg.toolCallId, 'ollama_tc_1');
    });

    // Parallel calls of the same tool in a single turn (e.g. two `read_file`s)
    // are a common agent pattern. Ollama's /api/chat does NOT use
    // `tool_call_id` — tool results are matched to tool calls by position
    // and `tool_name`. This test locks in two guarantees that keep that
    // matching safe:
    //   1. Each streamed tool call gets a unique synthesised id (so
    //      internal agent-core bookkeeping never conflates them).
    //   2. Arguments flow through unaltered (so positional ordering of
    //      outgoing tool results can be verified against inputs).
    test('parallel calls of the same tool in one turn get distinct ids and '
        'preserve arguments', () async {
      final events = [
        {
          'model': 'qwen3-coder:30b',
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'a.dart'},
                },
              },
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'b.dart'},
                },
              },
            ],
          },
          'done': false,
        },
        {
          'model': 'qwen3-coder:30b',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 40,
          'eval_count': 12,
        },
      ];

      final chunks = await OllamaClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(2));
      expect(starts[0].name, 'read_file');
      expect(starts[1].name, 'read_file');
      // Distinct IDs — proves no collision in synthesised bookkeeping.
      expect(starts[0].id, isNot(equals(starts[1].id)));

      final completes = chunks.whereType<ToolCallComplete>().toList();
      expect(completes, hasLength(2));
      expect(completes[0].toolCall.arguments['path'], 'a.dart');
      expect(completes[1].toolCall.arguments['path'], 'b.dart');
      // Arguments did not cross-contaminate across the two calls.
    });

    test(
      'emits ThinkingDelta for message.thinking (DeepSeek R1 / QwQ)',
      () async {
        final events = [
          {
            'message': {'role': 'assistant', 'thinking': 'step 1'},
            'done': false,
          },
          {
            'message': {'role': 'assistant', 'thinking': ' step 2'},
            'done': false,
          },
          {
            'message': {'role': 'assistant', 'content': 'done'},
            'done': true,
          },
        ];
        final chunks = await OllamaClient.parseStreamEvents(
          Stream.fromIterable(events),
        ).toList();
        expect(chunks.whereType<ThinkingDelta>().map((c) => c.text), [
          'step 1',
          ' step 2',
        ]);
        expect(chunks.whereType<TextDelta>().map((c) => c.text), ['done']);
      },
    );
  });

  group('OllamaClient.stream — error translation', () {
    test('400 + "does not support tools" body throws '
        'ToolsNotSupportedException with the model id', () async {
      final client = _FakeHttp(
        (_) async => _rawResponse(
          400,
          '{"error":"registry.ollama.ai/library/qwen2:0.5b does not '
          'support tools"}',
        ),
      );
      final ollama = OllamaClient(
        model: 'qwen2:0.5b',
        systemPrompt: '',
        requestClientFactory: () => client,
      );

      Object? caught;
      try {
        await ollama.stream([
          Message.user('hi'),
        ], tools: const <Tool>[]).toList();
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<ToolsNotSupportedException>());
      expect((caught! as ToolsNotSupportedException).modelId, 'qwen2:0.5b');
    });

    test('400 with unrelated body keeps the generic Exception path', () async {
      final client = _FakeHttp(
        (_) async => _rawResponse(400, '{"error":"context length exceeded"}'),
      );
      final ollama = OllamaClient(
        model: 'qwen3-coder:30b',
        systemPrompt: '',
        requestClientFactory: () => client,
      );

      Object? caught;
      try {
        await ollama.stream([Message.user('hi')]).toList();
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<Exception>());
      expect(caught, isNot(isA<ToolsNotSupportedException>()));
      expect(caught.toString(), contains('400'));
    });

    test('non-400 statuses keep the generic Exception path', () async {
      final client = _FakeHttp((_) async => _rawResponse(503, 'upstream gone'));
      final ollama = OllamaClient(
        model: 'qwen3-coder:30b',
        systemPrompt: '',
        requestClientFactory: () => client,
      );

      Object? caught;
      try {
        await ollama.stream([Message.user('hi')]).toList();
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<Exception>());
      expect(caught, isNot(isA<ToolsNotSupportedException>()));
      expect(caught.toString(), contains('503'));
    });
  });

  group('OllamaClient.stream — num_ctx resolution', () {
    // /api/show -> showJson (or 404 when null); /api/chat -> one done frame
    // with usage, capturing the chat request body into [chatBody].
    ({List<Map<String, dynamic>?> chatBody, _FakeHttp http}) harness({
      String? showJson,
    }) {
      final holder = <Map<String, dynamic>?>[null];
      final fake = _FakeHttp((req) async {
        if (req.url.path.endsWith('/api/show')) {
          return _rawResponse(showJson == null ? 404 : 200, showJson ?? 'no');
        }
        holder[0] =
            jsonDecode((req as http.Request).body) as Map<String, dynamic>;
        return _rawResponse(
          200,
          '${jsonEncode({
            'message': {'role': 'assistant', 'content': 'ok'},
            'done': true,
            'prompt_eval_count': 5,
            'eval_count': 2,
          })}\n',
        );
      });
      return (chatBody: holder, http: fake);
    }

    test(
      'exact catalog window is injected as num_ctx (no daemon call)',
      () async {
        final h = harness();
        final ollama = OllamaClient(
          model: 'gemma4:26b',
          systemPrompt: '',
          contextWindow: 256000,
          requestClientFactory: () => h.http,
        );
        await ollama.stream([Message.user('hi')]).toList();
        expect((h.chatBody[0]!['options'] as Map)['num_ctx'], 131072);
        expect(ollama.contextWindow, 256000);
      },
    );

    test('uncatalogued tag resolves via daemon /api/show', () async {
      final h = harness(
        showJson: jsonEncode({
          'model_info': {'gemma3.context_length': 32768},
        }),
      );
      final ollama = OllamaClient(
        model: 'gemma4:latest',
        systemPrompt: '',
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect((h.chatBody[0]!['options'] as Map)['num_ctx'], 32768);
      expect(ollama.contextWindow, 32768);
    });

    test('falls back to base-name hint when daemon has nothing', () async {
      final h = harness(); // /api/show -> 404
      final ollama = OllamaClient(
        model: 'gemma4:latest',
        systemPrompt: '',
        contextWindowFallback: 256000,
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect((h.chatBody[0]!['options'] as Map)['num_ctx'], 131072);
      expect(ollama.contextWindow, 256000);
    });

    test('default num_ctx when nothing resolves; getter stays null', () async {
      final h = harness(); // /api/show -> 404, no fallback
      final ollama = OllamaClient(
        model: 'mystery:latest',
        systemPrompt: '',
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect(
        (h.chatBody[0]!['options'] as Map)['num_ctx'],
        ollamaDefaultNumCtx,
      );
      expect(ollama.contextWindow, isNull);
    });
  });
}
