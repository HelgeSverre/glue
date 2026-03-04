import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/ndjson.dart';
import 'package:glue/src/llm/tool_schema.dart';

/// LLM client for Ollama local API with streaming.
///
/// Ollama uses NDJSON streaming (not SSE) and its own message format.
/// Tool calling uses OpenAI-compatible tool schemas but returns
/// arguments as parsed objects (not JSON strings).
///
/// {@category LLM Providers}
class OllamaClient implements LlmClient {
  final http.Client Function() _requestClientFactory;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  OllamaClient({
    required this.model,
    required this.systemPrompt,
    String baseUrl = 'http://localhost:11434',
    http.Client Function()? requestClientFactory,
  })  : _requestClientFactory = requestClientFactory ?? http.Client.new,
        _baseUri = Uri.parse(baseUrl);

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    // Per-request client: closing it aborts the TCP connection when the
    // stream subscription is cancelled, saving output tokens.
    final requestClient = _requestClientFactory();
    try {
      final mappedMessages = <Map<String, dynamic>>[];

      // System prompt as first message.
      if (systemPrompt.isNotEmpty) {
        mappedMessages.add({'role': 'system', 'content': systemPrompt});
      }

      for (final msg in messages) {
        switch (msg.role) {
          case Role.user:
            mappedMessages.add({'role': 'user', 'content': msg.text ?? ''});
          case Role.assistant:
            final entry = <String, dynamic>{
              'role': 'assistant',
              'content': msg.text ?? '',
            };
            if (msg.toolCalls.isNotEmpty) {
              entry['tool_calls'] = [
                for (final tc in msg.toolCalls)
                  {
                    'function': {
                      'name': tc.name,
                      'arguments': tc.arguments,
                    },
                  }
              ];
            }
            mappedMessages.add(entry);
          case Role.toolResult:
            final textContent = (msg.contentParts != null)
                ? ContentPart.textOnly(msg.contentParts!)
                : (msg.text ?? '');
            mappedMessages.add({
              'role': 'tool',
              'content':
                  textContent.isNotEmpty ? textContent : (msg.text ?? ''),
              'tool_name': msg.toolName ?? '',
            });
            if (msg.contentParts != null &&
                ContentPart.hasImages(msg.contentParts!)) {
              final images = msg.contentParts!
                  .whereType<ImagePart>()
                  .map((img) => img.toBase64())
                  .toList();
              mappedMessages.add({
                'role': 'user',
                'content': '[Screenshot from ${msg.toolName ?? "tool"}]',
                'images': images,
              });
            }
        }
      }

      final body = <String, dynamic>{
        'model': model,
        'messages': mappedMessages,
        'stream': true,
      };

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
      }

      final request = http.Request(
        'POST',
        _baseUri.resolve('/api/chat'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);

      final response = await requestClient.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception(
          'Ollama API error ${response.statusCode}: $errorBody',
        );
      }

      yield* parseStreamEvents(decodeNdjson(response.stream));
    } finally {
      requestClient.close();
    }
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
            final id = 'ollama_tc_$toolCallCounter';
            final name = fn['name'] as String;
            yield ToolCallStart(id: id, name: name);
            yield ToolCallComplete(ToolCall(
              id: id,
              name: name,
              // Ollama returns arguments as a parsed Map, not a JSON string.
              arguments: Map<String, dynamic>.from(fn['arguments'] as Map),
            ));
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
