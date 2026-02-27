import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../agent/tools.dart';
import 'message_mapper.dart';
import 'sse.dart';
import 'tool_schema.dart';

/// LLM client for OpenAI Chat Completions API with streaming.
class OpenAiClient implements LlmClient {
  final http.Client _http;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _defaultBaseUrl = 'https://api.openai.com';

  OpenAiClient({
    required http.Client httpClient,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
  })  : _http = httpClient,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final mapper = const OpenAiMessageMapper();
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

    final request = http.Request(
      'POST',
      _baseUri.resolve('/v1/chat/completions'),
    );
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    });
    request.body = jsonEncode(body);

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw Exception(
        'OpenAI API error ${response.statusCode}: $errorBody',
      );
    }

    yield* parseStreamEvents(
      decodeSse(response.stream).map(
        (e) => jsonDecode(e.data) as Map<String, dynamic>,
      ),
    );
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
          yield UsageInfo(
            inputTokens: (usage['prompt_tokens'] as int?) ?? 0,
            outputTokens: (usage['completion_tokens'] as int?) ?? 0,
          );
        }
        continue;
      }

      final choice = (choices.first as Map).cast<String, dynamic>();
      final delta = (choice['delta'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final finishReason = choice['finish_reason'] as String?;

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
            toolBuilders[index] = _ToolCallBuilder(
              id: (tcMap['id'] as String?) ?? 'call_$index',
              name: fn?['name'] as String? ?? '',
            );
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
          yield ToolCallDelta(ToolCall(
            id: builder.id,
            name: builder.name,
            arguments: args,
          ));
        }
        toolBuilders.clear();
      }

      // Usage in final chunk.
      if (usage != null) {
        yield UsageInfo(
          inputTokens: (usage['prompt_tokens'] as int?) ?? 0,
          outputTokens: (usage['completion_tokens'] as int?) ?? 0,
        );
      }
    }
  }
}

class _ToolCallBuilder {
  final String id;
  final String name;
  final StringBuffer argsBuffer = StringBuffer();
  _ToolCallBuilder({required this.id, required this.name});
}
