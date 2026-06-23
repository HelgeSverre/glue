import 'dart:async';
import 'package:http/http.dart' as http;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/message_mapper.dart';
import 'package:glue_strategies/src/llm/ndjson.dart';
import 'package:glue_strategies/src/llm/stream_request.dart';
import 'package:glue_strategies/src/llm/tool_schema.dart';
import 'package:glue_strategies/src/providers/ollama_discovery.dart';

/// Hard ceiling on the `num_ctx` override Glue will send.
///
/// Keeps us from forwarding absurd context windows (some catalogue entries
/// claim 1M+) that would blow past the user's RAM budget on mid-range
/// GPUs. 128K is comfortably above every real agent conversation and
/// matches what the upstream ecosystem (Continue, Cline, opencode) settled
/// on. Exposed publicly so tests can assert it without magic-number copies.
const int ollamaNumCtxCeiling = 131072;

/// Default `num_ctx` for Ollama models whose real context window cannot be
/// resolved from the catalog or the daemon. Anything but Ollama's silent
/// 2048 default; deliberately conservative so mid-range GPUs stay safe.
const int ollamaDefaultNumCtx = 8192;

/// LLM client for Ollama local API with streaming.
///
/// Ollama uses NDJSON streaming (not SSE) and its own message format.
/// Tool calling uses OpenAI-compatible tool schemas but returns
/// arguments as parsed objects (not JSON strings).
///
/// **`num_ctx` injection.** Ollama silently defaults to `num_ctx: 2048` for
/// every request regardless of what the model was trained with — a notorious
/// footgun that silently truncates agent loops. We resolve the model's real
/// window once (exact catalog → daemon `/api/show` → catalog base-name) and
/// **always** inject `options.num_ctx = min(resolved, ollamaNumCtxCeiling)`,
/// falling back to [ollamaDefaultNumCtx] (not 2048) when nothing resolves.
/// The resolved real window is exposed via [contextWindow] for the
/// context-occupancy gauge (null when only the default applied).
///
/// {@category LLM Providers}
class OllamaClient implements LlmClient, ContextWindowAware {
  final http.Client Function() _requestClientFactory;
  final String model;
  final String systemPrompt;

  /// Exact catalog context window, when the model id is catalogued. Null for
  /// passthrough tags (e.g. `gemma4:latest`).
  final int? _exactContextWindow;

  /// Base-name catalog hint from the adapter (`gemma4:latest` -> `gemma4:26b`).
  /// Used only when the daemon reports nothing.
  final int? _fallbackContextWindow;

  final Uri _baseUri;

  // Resolved once on the first stream(); see [_ensureResolved].
  bool _resolved = false;
  int? _resolvedRealWindow; // catalog/daemon/fallback — never the default
  int _numCtx = ollamaDefaultNumCtx;

  OllamaClient({
    required this.model,
    required this.systemPrompt,
    String baseUrl = 'http://localhost:11434',
    int? contextWindow,
    int? contextWindowFallback,
    http.Client Function()? requestClientFactory,
  }) : _exactContextWindow = contextWindow,
       _fallbackContextWindow = contextWindowFallback,
       _requestClientFactory = requestClientFactory ?? http.Client.new,
       _baseUri = Uri.parse(baseUrl);

  /// The real resolved window (catalog/daemon/fallback), or `null` when only
  /// the [ollamaDefaultNumCtx] guess applied — so the gauge never shows a
  /// made-up denominator. Populated after the first [stream] call.
  @override
  int? get contextWindow => _resolvedRealWindow;

  /// Resolve the real context window once: exact catalog -> daemon
  /// `/api/show` -> base-name fallback. Sizes [_numCtx] (capped at the
  /// ceiling), defaulting to [ollamaDefaultNumCtx] when nothing resolves so
  /// we never fall through to Ollama's silent 2048.
  Future<void> _ensureResolved() async {
    if (_resolved) return;
    _resolved = true;
    var real = _exactContextWindow;
    if (real == null || real <= 0) {
      final daemon = await OllamaDiscovery(
        baseUrl: _baseUri,
        clientFactory: _requestClientFactory,
      ).showContextLength(model);
      real = daemon ?? _fallbackContextWindow;
    }
    _resolvedRealWindow = (real != null && real > 0) ? real : null;
    final effective = _resolvedRealWindow ?? ollamaDefaultNumCtx;
    _numCtx = effective < ollamaNumCtxCeiling ? effective : ollamaNumCtxCeiling;
  }

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    // Resolve the window before the first request so num_ctx is always set
    // (never Ollama's silent 2048). createClient is synchronous, so this is
    // the earliest point we can await the daemon.
    await _ensureResolved();

    const mapper = OllamaMessageMapper();
    final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

    final body = <String, dynamic>{
      'model': model,
      'messages': mapped.messages,
      'stream': true,
      // Always injected (capped at the ceiling). _numCtx is the resolved
      // real window or the conservative default.
      'options': <String, dynamic>{'num_ctx': _numCtx},
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
    }

    yield* sendAndStream(
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
