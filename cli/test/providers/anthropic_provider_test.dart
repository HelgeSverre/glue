import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/llm/llm.dart';
import 'package:glue/src/providers/anthropic_provider.dart';
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

http.StreamedResponse _resp(int status, [Object body = const {}]) {
  final bytes = utf8.encode(body is String ? body : jsonEncode(body));
  return http.StreamedResponse(Stream<List<int>>.value(bytes), status);
}

const _anthropicProvider = ProviderDef(
  id: 'anthropic',
  name: 'Anthropic',
  adapter: 'anthropic',
  auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
  models: {},
);

void main() {
  group('AnthropicProvider (adapter role)', () {
    test('adapterId is "anthropic"', () {
      expect(AnthropicProvider().adapterId, 'anthropic');
    });

    test('createClient returns AnthropicProvider with the resolved apiKey', () {
      final adapter = AnthropicProvider();
      const provider = ProviderDef(
        id: 'anthropic',
        name: 'Anthropic',
        adapter: 'anthropic',
        auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
        models: {},
      );
      const model = ModelDef(id: 'claude-sonnet-4.6', name: 'Claude Sonnet');
      final client = adapter.createClient(
        provider: const ResolvedProvider(def: provider, apiKey: 'sk-test'),
        model: const ResolvedModel(def: model, provider: provider),
        systemPrompt: 'you are a helpful assistant',
      );
      expect(client, isA<AnthropicProvider>());
      expect((client as AnthropicProvider).apiKey, 'sk-test');
      expect(client.model, 'claude-sonnet-4.6');
      expect(client.systemPrompt, 'you are a helpful assistant');
    });

    test('validate returns missingCredential when apiKey is null', () {
      final adapter = AnthropicProvider();
      const provider = ProviderDef(
        id: 'anthropic',
        name: 'Anthropic',
        adapter: 'anthropic',
        auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
        models: {},
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: null)),
        ProviderHealth.missingCredential,
      );
      expect(
        adapter.validate(const ResolvedProvider(def: provider, apiKey: 'sk')),
        ProviderHealth.ok,
      );
    });

    test('probe forwards x-api-key + version on 200 → ok', () async {
      String? sentKey;
      String? sentVersion;
      Uri? captured;
      final adapter = AnthropicProvider(
        requestClientFactory: () => _FakeHttp((req) async {
          captured = req.url;
          sentKey = req.headers['x-api-key'];
          sentVersion = req.headers['anthropic-version'];
          return _resp(200, {'data': []});
        }),
      );
      final health = await adapter.probe(
        const ResolvedProvider(def: _anthropicProvider, apiKey: 'sk-good'),
      );
      expect(health, ProviderHealth.ok);
      expect(sentKey, 'sk-good');
      expect(sentVersion, '2023-06-01');
      expect(captured!.path, '/v1/models');
    });

    test('probe 401 → unauthorized', () async {
      final adapter = AnthropicProvider(
        requestClientFactory: () => _FakeHttp((_) async => _resp(401)),
      );
      final health = await adapter.probe(
        const ResolvedProvider(def: _anthropicProvider, apiKey: 'sk-bad'),
      );
      expect(health, ProviderHealth.unauthorized);
    });

    test('probe 500 → unreachable', () async {
      final adapter = AnthropicProvider(
        requestClientFactory: () => _FakeHttp((_) async => _resp(500)),
      );
      final health = await adapter.probe(
        const ResolvedProvider(def: _anthropicProvider, apiKey: 'sk-x'),
      );
      expect(health, ProviderHealth.unreachable);
    });

    test('probe missing key → missingCredential without HTTP', () async {
      final adapter = AnthropicProvider(
        requestClientFactory: () => _FakeHttp((_) async {
          fail('probe should not call HTTP without a key');
        }),
      );
      final health = await adapter.probe(
        const ResolvedProvider(def: _anthropicProvider, apiKey: null),
      );
      expect(health, ProviderHealth.missingCredential);
    });

    test('probe SocketException → unreachable', () async {
      final adapter = AnthropicProvider(
        requestClientFactory: () => _FakeHttp((_) async {
          throw const SocketException('refused');
        }),
      );
      final health = await adapter.probe(
        const ResolvedProvider(def: _anthropicProvider, apiKey: 'sk-x'),
      );
      expect(health, ProviderHealth.unreachable);
    });

    test('createClient honors custom base URL from ProviderDef', () {
      final adapter = AnthropicProvider();
      const provider = ProviderDef(
        id: 'anthropic-proxy',
        name: 'Proxy',
        adapter: 'anthropic',
        baseUrl: 'https://proxy.example.com',
        auth: AuthSpec(kind: AuthKind.none),
        models: {},
      );
      const model = ModelDef(id: 'claude', name: 'Claude');
      final client = adapter.createClient(
        provider: const ResolvedProvider(def: provider, apiKey: 'sk'),
        model: const ResolvedModel(def: model, provider: provider),
        systemPrompt: '',
      );
      expect(client, isA<AnthropicProvider>());
    });
  });

  group('AnthropicProvider.parseStreamEvents (client role)', () {
    test('parses text deltas from SSE events', () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {'input_tokens': 10, 'output_tokens': 0}
          }
        }),
        _sseData({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''}
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Hello '}
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'world'}
        }),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
          'usage': {'output_tokens': 5}
        }),
        _sseData({'type': 'message_stop'}),
      ];
      final chunks = await AnthropicProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final textDeltas = chunks.whereType<TextDelta>().toList();
      expect(textDeltas.map((d) => d.text).join(), 'Hello world');

      final usage = chunks.whereType<UsageInfo>().toList();
      expect(usage, isNotEmpty);
    });

    test('parses tool use blocks', () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {'input_tokens': 10, 'output_tokens': 0}
          }
        }),
        _sseData({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'tc1',
            'name': 'read_file'
          }
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"path"'}
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': ': "main.dart"}'
          }
        }),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 15}
        }),
        _sseData({'type': 'message_stop'}),
      ];

      final chunks = await AnthropicProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final toolCalls = chunks.whereType<ToolCallComplete>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolCall.name, 'read_file');
      expect(toolCalls.first.toolCall.arguments['path'], 'main.dart');
    });

    test('emits ToolCallStart before ToolCallComplete', () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {'input_tokens': 10, 'output_tokens': 0}
          }
        }),
        _sseData({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'tool_use',
            'id': 'tc1',
            'name': 'write_file'
          }
        }),
        _sseData({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': '{"path": "a.txt"}'
          }
        }),
        _sseData({'type': 'content_block_stop', 'index': 0}),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 10}
        }),
        _sseData({'type': 'message_stop'}),
      ];

      final chunks = await AnthropicProvider.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final starts = chunks.whereType<ToolCallStart>().toList();
      expect(starts, hasLength(1));
      expect(starts.first.id, 'tc1');
      expect(starts.first.name, 'write_file');

      // ToolCallStart must come before ToolCallComplete
      final startIdx = chunks.indexWhere((c) => c is ToolCallStart);
      final deltaIdx = chunks.indexWhere((c) => c is ToolCallComplete);
      expect(startIdx, lessThan(deltaIdx));
    });
  });
}

Map<String, dynamic> _sseData(Map<String, dynamic> payload) => payload;
