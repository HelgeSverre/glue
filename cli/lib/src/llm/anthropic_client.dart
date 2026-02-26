import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../agent/tools.dart';
import 'message_mapper.dart';
import 'sse.dart';
import 'tool_schema.dart';

/// LLM client for the Anthropic Messages API with streaming.
class AnthropicClient implements LlmClient {
  final http.Client _http;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _apiVersion = '2023-06-01';
  static const _defaultBaseUrl = 'https://api.anthropic.com';

  AnthropicClient({
    required http.Client httpClient,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
  })  : _http = httpClient,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final mapper = const AnthropicMessageMapper();
    final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 8192,
      'stream': true,
      'system': mapped.systemPrompt,
      'messages': mapped.messages,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const AnthropicToolEncoder().encodeAll(tools);
    }

    final request = http.Request(
      'POST',
      _baseUri.resolve('/v1/messages'),
    );
    request.headers.addAll({
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': _apiVersion,
    });
    request.body = jsonEncode(body);

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
        'Anthropic API error ${response.statusCode}: $errorBody',
      );
    }

    yield* parseStreamEvents(
      decodeSse(response.stream).map(
        (e) => jsonDecode(e.data) as Map<String, dynamic>,
      ),
    );
  }

  /// Parse Anthropic SSE event payloads into [LlmChunk]s.
  ///
  /// Exposed as static for testability (can feed synthetic events).
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    // Buffer for accumulating partial tool use input JSON.
    final toolBuffers = <int, _ToolUseBuffer>{};
    int inputTokens = 0;
    int outputTokens = 0;

    await for (final event in events) {
      final type = event['type'] as String?;

      switch (type) {
        case 'message_start':
          final usage = (event['message'] as Map?)?['usage'] as Map?;
          if (usage != null) {
            inputTokens = (usage['input_tokens'] as int?) ?? 0;
          }

        case 'content_block_start':
          final index = event['index'] as int;
          final block = event['content_block'] as Map<String, dynamic>;
          if (block['type'] == 'tool_use') {
            toolBuffers[index] = _ToolUseBuffer(
              id: block['id'] as String,
              name: block['name'] as String,
            );
          }

        case 'content_block_delta':
          final index = event['index'] as int;
          final delta = event['delta'] as Map<String, dynamic>;
          final deltaType = delta['type'] as String?;

          if (deltaType == 'text_delta') {
            yield TextDelta(delta['text'] as String);
          } else if (deltaType == 'input_json_delta') {
            toolBuffers[index]?.buffer.write(delta['partial_json'] as String);
          }

        case 'content_block_stop':
          final index = event['index'] as int;
          final buf = toolBuffers.remove(index);
          if (buf != null) {
            final argsJson = buf.buffer.toString();
            Map<String, dynamic> args;
            try {
              args = argsJson.isNotEmpty
                  ? (jsonDecode(argsJson) as Map<String, dynamic>)
                  : <String, dynamic>{};
            } on FormatException {
              args = <String, dynamic>{'_raw': argsJson};
            }
            yield ToolCallDelta(ToolCall(
              id: buf.id,
              name: buf.name,
              arguments: args,
            ));
          }

        case 'message_delta':
          final usage = event['usage'] as Map?;
          if (usage != null) {
            outputTokens = (usage['output_tokens'] as int?) ?? 0;
          }

        case 'message_stop':
          yield UsageInfo(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
          );
      }
    }
  }
}

class _ToolUseBuffer {
  final String id;
  final String name;
  final StringBuffer buffer = StringBuffer();
  _ToolUseBuffer({required this.id, required this.name});
}
