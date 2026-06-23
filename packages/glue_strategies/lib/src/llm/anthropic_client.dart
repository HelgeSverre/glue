import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/message_mapper.dart';
import 'package:glue_strategies/src/llm/sse.dart';
import 'package:glue_strategies/src/llm/stream_request.dart';
import 'package:glue_strategies/src/llm/tool_args.dart';
import 'package:glue_strategies/src/llm/tool_schema.dart';

/// LLM client for the Anthropic Messages API with streaming.
///
/// Prompt caching: when [promptCacheEnabled] is true (default), the
/// request body includes a top-level `cache_control: {type: "ephemeral"}`
/// directive. Anthropic's auto-caching advances the cache breakpoint to
/// the last cacheable block on each turn, so a growing conversation
/// accumulates cache hits without the client tracking breakpoint
/// placement explicitly. Caching is GA on Claude 4.x — no beta header
/// needed. Older models silently ignore the directive.
///
/// {@category LLM Providers}
class AnthropicClient implements LlmClient {
  final http.Client Function() _requestClientFactory;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;
  final bool promptCacheEnabled;

  static const _apiVersion = '2023-06-01';
  static const _defaultBaseUrl = 'https://api.anthropic.com';

  AnthropicClient({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
    http.Client Function()? requestClientFactory,
    this.promptCacheEnabled = true,
  }) : _requestClientFactory = requestClientFactory ?? http.Client.new,
       _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) {
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

    if (promptCacheEnabled) {
      // Top-level auto-caching: Anthropic advances the cache breakpoint
      // to the last cacheable block (system → tools → messages) so the
      // largest stable prefix accrues cache hits across turns. No
      // mapper changes needed; older models that don't support caching
      // silently ignore this field.
      body['cache_control'] = {'type': 'ephemeral'};
    }

    return sendAndStream(
      requestClientFactory: _requestClientFactory,
      uri: _baseUri.resolve('/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': _apiVersion,
      },
      body: body,
      providerName: 'Anthropic',
      parse: (bytes) => parseStreamEvents(
        decodeSse(bytes).map((e) => jsonDecode(e.data) as Map<String, dynamic>),
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
    final toolBuffers = <int, ToolArgsBuffer<ToolCallId>>{};
    int inputTokens = 0;
    int outputTokens = 0;
    int? cacheReadTokens;
    int? cacheCreationTokens;

    await for (final event in events) {
      final type = event['type'] as String?;

      switch (type) {
        case 'message_start':
          final usage = (event['message'] as Map?)?['usage'] as Map?;
          if (usage != null) {
            inputTokens = (usage['input_tokens'] as int?) ?? 0;
            // Per current Anthropic docs, the message_start usage block
            // carries cache statistics. Both fields may be absent on a
            // cold cache or on providers that proxy without forwarding
            // them — leave the locals null in that case so UsageInfo
            // distinguishes "not reported" from "zero".
            final cacheRead = usage['cache_read_input_tokens'];
            if (cacheRead is int) cacheReadTokens = cacheRead;
            final cacheCreate = usage['cache_creation_input_tokens'];
            if (cacheCreate is int) cacheCreationTokens = cacheCreate;
          }

        case 'content_block_start':
          final index = event['index'] as int;
          final block = event['content_block'] as Map<String, dynamic>;
          if (block['type'] == 'tool_use') {
            final id = ToolCallId(block['id'] as String);
            final name = block['name'] as String;
            toolBuffers[index] = ToolArgsBuffer(id: id, name: name);
            yield ToolCallStart(id: id, name: name);
          }

        case 'content_block_delta':
          final index = event['index'] as int;
          final delta = event['delta'] as Map<String, dynamic>;
          final deltaType = delta['type'] as String?;

          if (deltaType == 'text_delta') {
            yield TextDelta(delta['text'] as String);
          } else if (deltaType == 'thinking_delta') {
            // Extended-thinking blocks. `redacted_thinking` blocks (base64
            // signed payloads for safety-sensitive reasoning) carry no
            // human-readable content and are intentionally ignored here.
            final thinking = delta['thinking'];
            if (thinking is String && thinking.isNotEmpty) {
              yield ThinkingDelta(thinking);
            }
          } else if (deltaType == 'input_json_delta') {
            toolBuffers[index]?.write(delta['partial_json'] as String);
          }

        case 'content_block_stop':
          final index = event['index'] as int;
          final buf = toolBuffers.remove(index);
          if (buf != null) {
            yield ToolCallComplete(
              ToolCall(
                id: buf.id,
                name: buf.name,
                arguments: buf.finalizeArguments(),
              ),
            );
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
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
          );
      }
    }
  }
}
