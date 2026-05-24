import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/message_mapper.dart';
import 'package:glue_strategies/src/llm/sse.dart';
import 'package:glue_strategies/src/llm/tool_schema.dart';
import 'package:glue_strategies/src/providers/compatibility_profile.dart';

/// LLM client for OpenAI Chat Completions API with streaming.
///
/// Compatibility quirks of OpenAI-shaped endpoints (Groq, Ollama, OpenRouter,
/// vLLM, Mistral) are handled by the injected [CompatibilityProfile] — this
/// client stays protocol-shaped and does not branch on vendor id.
///
/// {@category LLM Providers}
class OpenAiClient implements LlmClient {
  final http.Client Function() _requestClientFactory;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final String baseUrl;
  final CompatibilityProfile profile;
  final Map<String, String> extraHeaders;
  final Uri _baseUri;

  OpenAiClient({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.baseUrl,
    this.profile = CompatibilityProfile.openai,
    this.extraHeaders = const {},
    http.Client Function()? requestClientFactory,
  }) : _requestClientFactory = requestClientFactory ?? http.Client.new,
       _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    // Per-request client: closing it aborts the TCP connection when the
    // stream subscription is cancelled, saving output tokens.
    final requestClient = _requestClientFactory();
    try {
      const mapper = OpenAiMessageMapper();
      final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

      final body = <String, dynamic>{
        'model': model,
        'stream': true,
        'stream_options': {'include_usage': true},
        'messages': mapped.messages,
      };

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
      }

      profile.mutateBody(body);

      final endpointBase = _baseUri.path.endsWith('/')
          ? _baseUri
          : _baseUri.replace(path: '${_baseUri.path}/');
      final request = http.Request(
        'POST',
        endpointBase.resolve('chat/completions'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        ...extraHeaders,
      });
      request.body = jsonEncode(body);

      final response = await requestClient.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('OpenAI API error ${response.statusCode}: $errorBody');
      }

      yield* parseStreamEvents(
        decodeSse(
          response.stream,
        ).map((e) => jsonDecode(e.data) as Map<String, dynamic>),
      );
    } finally {
      requestClient.close();
    }
  }

  /// Parse OpenAI streaming chunks into [LlmChunk]s.
  ///
  /// Exposed as static for testability.
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    // Accumulate streamed tool call arguments.
    final toolBuilders = <int, _ToolCallBuilder>{};

    await for (final event in events) {
      // Usage may come in a final chunk.
      final usageRaw = event['usage'] as Map?;
      final usage = usageRaw?.cast<String, dynamic>();

      final choices = event['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        // Usage-only chunk (stream_options.include_usage).
        if (usage != null) {
          yield _usageInfoFromOpenAi(usage);
        }
        continue;
      }

      final choice = (choices.first as Map).cast<String, dynamic>();
      final delta =
          (choice['delta'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final finishReason = choice['finish_reason'] as String?;

      // Reasoning ("thinking") content. GPT-5 / o-series put it on
      // `delta.reasoning`; some gateways and DeepSeek use
      // `delta.reasoning_content`. A single delta object can carry both
      // reasoning and content, so this branch precedes the content check.
      final reasoning = delta['reasoning'] ?? delta['reasoning_content'];
      if (reasoning is String && reasoning.isNotEmpty) {
        yield ThinkingDelta(reasoning);
      }

      // Text content.
      final content = delta['content'] as String?;
      if (content != null && content.isNotEmpty) {
        yield TextDelta(content);
      }

      // Tool calls (streamed incrementally).
      final toolCalls = delta['tool_calls'] as List?;
      if (toolCalls != null) {
        for (final tc in toolCalls) {
          final tcMap = (tc as Map).cast<String, dynamic>();
          final index = tcMap['index'] as int;
          final fn = (tcMap['function'] as Map?)?.cast<String, dynamic>();

          if (!toolBuilders.containsKey(index)) {
            final id = ToolCallId((tcMap['id'] as String?) ?? 'call_$index');
            final name = fn?['name'] as String? ?? '';
            toolBuilders[index] = _ToolCallBuilder(id: id, name: name);
            yield ToolCallStart(id: id, name: name);
          }

          final args = fn?['arguments'] as String?;
          if (args != null) {
            toolBuilders[index]!.argsBuffer.write(args);
          }
        }
      }

      // On finish, emit completed tool calls.
      if (finishReason != null && toolBuilders.isNotEmpty) {
        for (final builder in toolBuilders.values) {
          final argsStr = builder.argsBuffer.toString();
          Map<String, dynamic> args;
          try {
            args = argsStr.isNotEmpty
                ? (jsonDecode(argsStr) as Map<String, dynamic>)
                : <String, dynamic>{};
          } on FormatException {
            args = <String, dynamic>{'_raw': argsStr};
          }
          yield ToolCallComplete(
            ToolCall(id: builder.id, name: builder.name, arguments: args),
          );
        }
        toolBuilders.clear();
      }

      // Usage in final chunk.
      if (usage != null) {
        yield _usageInfoFromOpenAi(usage);
      }
    }
  }
}

/// Parses a Chat Completions / OpenRouter `usage` object into [UsageInfo].
///
/// Handles three shapes encountered in practice:
///
/// - **Native OpenAI**: `prompt_tokens`, `completion_tokens`, optional
///   `prompt_tokens_details.cached_tokens` for hit count. No equivalent
///   of `cache_creation_input_tokens` — OpenAI's cache is fully managed
///   server-side.
/// - **OpenRouter (any upstream)**: same as above, plus a top-level
///   `cache_write_tokens` populated when the upstream is Anthropic and a
///   write occurred. Kept null on OpenAI upstream where caching is fully
///   automatic.
/// - **Proxies that forward Anthropic shape**: surface
///   `cache_creation_input_tokens` / `cache_read_input_tokens` if seen,
///   but the OpenAI-shaped path is the primary expectation.
UsageInfo _usageInfoFromOpenAi(Map<String, dynamic> usage) {
  final promptDetails = (usage['prompt_tokens_details'] as Map?)
      ?.cast<String, dynamic>();
  final cachedTokens = promptDetails?['cached_tokens'] as int?;
  final cacheWriteOpenRouter = usage['cache_write_tokens'] as int?;
  final cacheCreateAnthropic = usage['cache_creation_input_tokens'] as int?;
  return UsageInfo(
    inputTokens: (usage['prompt_tokens'] as int?) ?? 0,
    outputTokens: (usage['completion_tokens'] as int?) ?? 0,
    cacheReadTokens: cachedTokens ?? (usage['cache_read_input_tokens'] as int?),
    cacheCreationTokens: cacheWriteOpenRouter ?? cacheCreateAnthropic,
  );
}

class _ToolCallBuilder {
  final ToolCallId id;
  final String name;
  final StringBuffer argsBuffer = StringBuffer();
  _ToolCallBuilder({required this.id, required this.name});
}
