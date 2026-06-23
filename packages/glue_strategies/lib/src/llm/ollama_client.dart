import 'dart:async';
import 'package:http/http.dart' as http;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/message_mapper.dart';
import 'package:glue_strategies/src/llm/ndjson.dart';
import 'package:glue_strategies/src/llm/stream_request.dart';
import 'package:glue_strategies/src/llm/tool_schema.dart';

/// Hard ceiling on the `num_ctx` override Glue will send.
///
/// Keeps us from forwarding absurd context windows (some catalogue entries
/// claim 1M+) that would blow past the user's RAM budget on mid-range
/// GPUs. 128K is comfortably above every real agent conversation and
/// matches what the upstream ecosystem (Continue, Cline, opencode) settled
/// on. Exposed publicly so tests can assert it without magic-number copies.
const int ollamaNumCtxCeiling = 131072;

/// LLM client for Ollama local API with streaming.
///
/// Ollama uses NDJSON streaming (not SSE) and its own message format.
/// Tool calling uses OpenAI-compatible tool schemas but returns
/// arguments as parsed objects (not JSON strings).
///
/// **`num_ctx` injection.** Ollama silently defaults to `num_ctx: 2048` for
/// every request regardless of what the model was trained with — a
/// notorious footgun that silently truncates agent loops. When [contextWindow]
/// is set, we inject `options.num_ctx = min(contextWindow, ollamaNumCtxCeiling)`
/// so catalogued models get the full context their metadata promises.
///
/// {@category LLM Providers}
class OllamaClient implements LlmClient {
  final http.Client Function() _requestClientFactory;
  final String model;
  final String systemPrompt;

  /// When non-null, injected as `options.num_ctx` on every request. Comes
  /// from `ModelDef.contextWindow` at adapter construction time. See class
  /// doc for why this matters.
  final int? contextWindow;

  final Uri _baseUri;

  OllamaClient({
    required this.model,
    required this.systemPrompt,
    String baseUrl = 'http://localhost:11434',
    this.contextWindow,
    http.Client Function()? requestClientFactory,
  }) : _requestClientFactory = requestClientFactory ?? http.Client.new,
       _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) {
    const mapper = OllamaMessageMapper();
    final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

    final body = <String, dynamic>{
      'model': model,
      'messages': mapped.messages,
      'stream': true,
    };

    if (contextWindow != null && contextWindow! > 0) {
      // Cap to a reasonable ceiling regardless of catalog claims so we
      // don't OOM mid-range GPUs with 1M-context settings.
      final numCtx = contextWindow! < ollamaNumCtxCeiling
          ? contextWindow!
          : ollamaNumCtxCeiling;
      body['options'] = <String, dynamic>{'num_ctx': numCtx};
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
    }

    return sendAndStream(
      requestClientFactory: _requestClientFactory,
      uri: _baseUri.resolve('/api/chat'),
      headers: const {'Content-Type': 'application/json'},
      body: body,
      providerName: 'Ollama',
      parse: (bytes) => parseStreamEvents(decodeNdjson(bytes)),
      classifyError: (status, errorBody) {
        // Ollama returns 400 with body containing "does not support tools"
        // when the loaded model has no function-calling support but we
        // sent a `tools` array. Surface this as a typed exception so the
        // agent loop can soft-degrade to chat-only instead of crashing.
        // Loose match — body shape is `{"error":"<model> does not support tools"}`
        // today but stay defensive about wording drift.
        if (status == 400 &&
            errorBody.toLowerCase().contains('does not support tools')) {
          throw ToolsNotSupportedException(model);
        }
        throw Exception('Ollama API error $status: $errorBody');
      },
    );
  }

  /// Parse Ollama NDJSON streaming events into [LlmChunk]s.
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    int toolCallCounter = 0;

    await for (final event in events) {
      final messageRaw = event['message'] as Map?;
      final message = messageRaw?.cast<String, dynamic>();
      final done = event['done'] as bool? ?? false;

      if (message != null) {
        // Reasoning content for thinking-capable models (DeepSeek R1,
        // QwQ, …). Precedes `content` because a single message chunk
        // can carry both fields.
        final thinking = message['thinking'] as String?;
        if (thinking != null && thinking.isNotEmpty) {
          yield ThinkingDelta(thinking);
        }

        // Text content.
        final content = message['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield TextDelta(content);
        }

        // Tool calls — Ollama delivers them fully formed (not streamed incrementally).
        final toolCalls = message['tool_calls'] as List?;
        if (toolCalls != null) {
          for (final tc in toolCalls) {
            final fn = (tc as Map).cast<String, dynamic>()['function'] as Map;
            toolCallCounter++;
            final id = ToolCallId('ollama_tc_$toolCallCounter');
            final name = fn['name'] as String;
            yield ToolCallStart(id: id, name: name);
            yield ToolCallComplete(
              ToolCall(
                id: id,
                name: name,
                // Ollama returns arguments as a parsed Map, not a JSON string.
                arguments: Map<String, dynamic>.from(fn['arguments'] as Map),
              ),
            );
          }
        }
      }

      // Final chunk contains token counts.
      if (done) {
        final promptTokens = event['prompt_eval_count'] as int? ?? 0;
        final evalTokens = event['eval_count'] as int? ?? 0;
        yield UsageInfo(inputTokens: promptTokens, outputTokens: evalTokens);
      }
    }
  }
}
