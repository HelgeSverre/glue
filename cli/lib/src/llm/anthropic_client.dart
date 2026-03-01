import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/dev/devtools.dart';
import 'package:glue/src/llm/message_mapper.dart';
import 'package:glue/src/llm/sse.dart';
import 'package:glue/src/llm/tool_schema.dart';

/// LLM client for the Anthropic Messages API with streaming.
///
/// {@category LLM Providers}
class AnthropicClient implements LlmClient {
  final http.Client Function() _requestClientFactory;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _apiVersion = '2023-06-01';
  static const _defaultBaseUrl = 'https://api.anthropic.com';

  AnthropicClient({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
    http.Client Function()? requestClientFactory,
  })  : _requestClientFactory = requestClientFactory ?? http.Client.new,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    // Per-request client: closing it aborts the TCP connection when the
    // stream subscription is cancelled, saving output tokens.
    final requestClient = _requestClientFactory();
    try {
      const mapper = AnthropicMessageMapper();
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

      final task = GlueDev.startAsync('LLM Anthropic', args: {'model': model});
      final stopwatch = Stopwatch()..start();
      GlueDev.log('llm.request', 'Anthropic $model stream start');

      final response = await requestClient.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        task.finish(arguments: {'error': response.statusCode.toString()});
        throw Exception(
          'Anthropic API error ${response.statusCode}: $errorBody',
        );
      }

      int? ttfbMs;
      int inputTokens = 0;
      int outputTokens = 0;

      await for (final chunk in parseStreamEvents(
        decodeSse(response.stream).map(
          (e) => jsonDecode(e.data) as Map<String, dynamic>,
        ),
      )) {
        if (ttfbMs == null && chunk is TextDelta) {
          ttfbMs = stopwatch.elapsedMilliseconds;
        }
        if (chunk is UsageInfo) {
          inputTokens = chunk.inputTokens;
          outputTokens = chunk.outputTokens;
        }
        yield chunk;
      }

      final totalMs = stopwatch.elapsedMilliseconds;
      stopwatch.stop();
      task.finish(arguments: {
        'ttfbMs': ttfbMs ?? totalMs,
        'totalMs': totalMs,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
      });
      GlueDev.postLlmRequest(
        provider: 'anthropic',
        model: model,
        ttfbMs: ttfbMs ?? totalMs,
        streamDurationMs: totalMs,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      );
    } finally {
      requestClient.close();
    }
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
            final id = block['id'] as String;
            final name = block['name'] as String;
            toolBuffers[index] = _ToolUseBuffer(id: id, name: name);
            yield ToolCallStart(id: id, name: name);
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
