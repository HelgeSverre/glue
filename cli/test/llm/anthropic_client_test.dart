import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/glue_harness.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('AnthropicClient request body', () {
    test('sends top-level cache_control when promptCacheEnabled is true',
        () async {
      final captured = _CapturingHttpClient(_minimalSseResponse());
      final client = AnthropicClient(
        apiKey: 'sk-test',
        model: 'claude-sonnet-4-6',
        systemPrompt: 'You are Glue.',
        requestClientFactory: () => captured,
      );

      await client.stream([Message.user('hi')]).drain<void>();

      final body = jsonDecode(captured.body!) as Map<String, dynamic>;
      expect(body['cache_control'], {'type': 'ephemeral'});
      // Caching is GA on Claude 4.x; the legacy beta header must be absent.
      expect(captured.headers, isNot(contains('anthropic-beta')));
    });

    test('omits cache_control when promptCacheEnabled is false', () async {
      final captured = _CapturingHttpClient(_minimalSseResponse());
      final client = AnthropicClient(
        apiKey: 'sk-test',
        model: 'claude-sonnet-4-6',
        systemPrompt: 'You are Glue.',
        requestClientFactory: () => captured,
        promptCacheEnabled: false,
      );

      await client.stream([Message.user('hi')]).drain<void>();

      final body = jsonDecode(captured.body!) as Map<String, dynamic>;
      expect(body.containsKey('cache_control'), isFalse);
    });
  });

  group('AnthropicClient.parseStream', () {
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
      final chunks = await AnthropicClient.parseStreamEvents(
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

      final chunks = await AnthropicClient.parseStreamEvents(
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

      final chunks = await AnthropicClient.parseStreamEvents(
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

    test('surfaces cache_read and cache_creation tokens from message_start',
        () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {
              'input_tokens': 12,
              'cache_read_input_tokens': 9500,
              'cache_creation_input_tokens': 800,
              'output_tokens': 0,
            }
          }
        }),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
          'usage': {'output_tokens': 42}
        }),
        _sseData({'type': 'message_stop'}),
      ];

      final chunks = await AnthropicClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList();

      final usage = chunks.whereType<UsageInfo>().single;
      expect(usage.inputTokens, 12);
      expect(usage.outputTokens, 42);
      expect(usage.cacheReadTokens, 9500);
      expect(usage.cacheCreationTokens, 800);
    });

    test('leaves cache fields null when the provider omits them', () async {
      final events = [
        _sseData({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'usage': {'input_tokens': 12, 'output_tokens': 0}
          }
        }),
        _sseData({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
          'usage': {'output_tokens': 7}
        }),
        _sseData({'type': 'message_stop'}),
      ];

      final usage = (await AnthropicClient.parseStreamEvents(
        Stream.fromIterable(events),
      ).toList())
          .whereType<UsageInfo>()
          .single;

      expect(usage.cacheReadTokens, isNull);
      expect(usage.cacheCreationTokens, isNull);
    });
  });
}

Map<String, dynamic> _sseData(Map<String, dynamic> payload) => payload;

/// Smallest valid Anthropic SSE response: an empty assistant turn that
/// goes straight to `message_stop`. Sufficient for request-shape tests
/// that don't care about the streamed content.
String _minimalSseResponse() {
  String event(Map<String, dynamic> data) => 'data: ${jsonEncode(data)}\n\n';
  return [
    event({
      'type': 'message_start',
      'message': {
        'id': 'm-test',
        'usage': {'input_tokens': 1, 'output_tokens': 0},
      },
    }),
    event({
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 0},
    }),
    event({'type': 'message_stop'}),
  ].join();
}

class _CapturingHttpClient extends http.BaseClient {
  _CapturingHttpClient(this._sseBody);

  final String _sseBody;
  String? body;
  Map<String, String>? headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      body = request.body;
    }
    headers = request.headers;
    final bytes = utf8.encode(_sseBody);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      contentLength: bytes.length,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}
