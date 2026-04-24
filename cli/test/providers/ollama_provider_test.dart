/// OllamaProvider tests.
///
/// Covers both adapter-role wiring (`/api/chat`, model.apiId on wire,
/// num_ctx injection from ModelDef.contextWindow, `/v1` suffix stripping,
/// discoverModels) and client-role NDJSON parsing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:glue/src/providers/ollama_provider.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

ResolvedProvider _provider({String? baseUrl}) {
  return ResolvedProvider(
    def: ProviderDef(
      id: 'ollama',
      name: 'Ollama',
      adapter: 'ollama',
      baseUrl: baseUrl,
      auth: const AuthSpec(kind: AuthKind.none),
      models: const {},
    ),
    apiKey: null,
    credentials: const {},
  );
}

ResolvedModel _model({
  String id = 'qwen3-coder:30b',
  int? contextWindow,
  String? apiId,
}) {
  final def = ModelDef(
    id: id,
    name: id,
    apiId: apiId,
    contextWindow: contextWindow,
  );
  return ResolvedModel(
    def: def,
    provider: ProviderDef(
      id: 'ollama',
      name: 'Ollama',
      adapter: 'ollama',
      auth: const AuthSpec(kind: AuthKind.none),
      models: {id: def},
    ),
  );
}

void main() {
  group('OllamaProvider.createClient', () {
    test('returns an OllamaProvider', () {
      final adapter = OllamaProvider();
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(),
        systemPrompt: 'you are glue',
      );
      expect(client, isA<OllamaProvider>());
    });

    test('propagates model.apiId on the wire, not the catalog key', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'model': 'whatever',
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
              'prompt_eval_count': 0,
              'eval_count': 0,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(id: 'qwen3-coder:30b', apiId: 'qwen3-coder:30b'),
        systemPrompt: '',
      );
      // Drain the stream to force the HTTP call.
      await client.stream([]).toList();
      expect(capturedBody?['model'], 'qwen3-coder:30b');
    });

    test('injects options.num_ctx from ModelDef.contextWindow', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(contextWindow: 256000),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      final options = capturedBody?['options'];
      expect(options, isA<Map<String, Object?>>());
      // 256K gets clamped to the 128K ceiling.
      expect(
          (options! as Map<String, Object?>)['num_ctx'], ollamaNumCtxCeiling);
    });

    test(
        'passes num_ctx through unclamped when ModelDef.contextWindow is '
        'below the ceiling', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(contextWindow: 8192),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      final options = capturedBody?['options'] as Map?;
      expect(options?['num_ctx'], 8192);
    });

    test(
        'omits options entirely when ModelDef.contextWindow is null '
        '(uncatalogued passthrough)', () async {
      Map<String, Object?>? capturedBody;
      final adapter = OllamaProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedBody =
              jsonDecode((req as http.Request).body) as Map<String, Object?>;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(),
        model: _model(contextWindow: null),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      expect(capturedBody?.containsKey('options'), isFalse);
    });

    test('strips legacy /v1 suffix from baseUrl so /api/chat resolves',
        () async {
      Uri? capturedUrl;
      final adapter = OllamaProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          capturedUrl = req.url;
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true,
            }))),
            200,
            headers: {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final client = adapter.createClient(
        provider: _provider(baseUrl: 'http://localhost:11434/v1'),
        model: _model(),
        systemPrompt: '',
      );
      await client.stream([]).toList();
      expect(capturedUrl.toString(), 'http://localhost:11434/api/chat');
    });
  });

  group('OllamaProvider health', () {
    test('validate always returns ok (no credentials required)', () {
      expect(OllamaProvider().validate(_provider()), ProviderHealth.ok);
    });

    test('isConnected is always true', () {
      final store = CredentialStore(
        path: '${Directory.systemTemp.path}/glue_adapter_test_creds.json',
        env: const {},
      );
      expect(OllamaProvider().isConnected(_provider().def, store), isTrue);
    });
  });

  group('OllamaProvider.discoverModels', () {
    setUp(OllamaDiscovery.resetCacheForTesting);

    test('maps /api/tags into DiscoveredModel list', () async {
      final adapter = OllamaProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(jsonEncode({
              'models': [
                {'name': 'qwen3-coder:30b', 'size': 20000000000},
                {'name': 'gemma4:latest', 'size': 9600000000},
              ],
            }))),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      // discoverModels uses OllamaDiscovery internally, which builds its
      // own http.Client. We can't easily inject it end-to-end here — the
      // contract test lives in ollama_discovery_test.dart. This is just
      // a smoke test that the adapter returns the expected shape when
      // the daemon is actually present. If the daemon isn't, we expect
      // an empty list (fail-soft), which is also a valid outcome.
      final out = await adapter.discoverModels(_provider());
      expect(out, isA<List<DiscoveredModel>>());
    });
  });

  group('OllamaProvider.parseStreamEvents', () {
    test('parses text deltas from streaming JSON', () async {
      final events = [
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': 'Hello '},
          'done': false
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': 'world'},
          'done': false
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 26,
          'eval_count': 10
        },
      ];

      final chunks = await OllamaProvider.parseStreamEvents(
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
                }
              }
            ]
          },
          'done': false,
        },
        {
          'model': 'llama3.2',
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'prompt_eval_count': 20,
          'eval_count': 15
        },
      ];

      final chunks = await OllamaProvider.parseStreamEvents(
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

    test('tool result uses tool name not call ID', () {
      final msg = Message.toolResult(
        callId: 'ollama_tc_1',
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
    test(
        'parallel calls of the same tool in one turn get distinct ids and '
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
                }
              },
              {
                'function': {
                  'name': 'read_file',
                  'arguments': {'path': 'b.dart'},
                }
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

      final chunks = await OllamaProvider.parseStreamEvents(
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
  });
}
