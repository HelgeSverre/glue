import 'dart:async';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/llm/llm.dart';
import 'package:glue/src/providers/anthropic_provider.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:test/test.dart';

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
