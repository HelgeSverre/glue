/// Streaming client for the Gemini Developer API (`v1beta`).
///
/// Talks to `generativelanguage.googleapis.com` via SSE streams. Unlike
/// the other built-in LLM clients this also doubles as the data-parser
/// that [GeminiProvider] delegates to — `parseStreamEvents` is exposed
/// as a static for testability.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/message_mapper.dart';
import 'package:glue_strategies/src/llm/sse.dart';
import 'package:glue_strategies/src/llm/tool_schema.dart';
import 'package:http/http.dart' as http;

class GeminiClient implements LlmClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    String baseUrl = _defaultBaseUrl,
    http.Client Function()? requestClientFactory,
  }) : _requestClientFactory = requestClientFactory ?? http.Client.new,
       _baseUri = Uri.parse(baseUrl);

  final http.Client Function() _requestClientFactory;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _apiVersion = 'v1beta';
  static const _defaultBaseUrl = 'https://generativelanguage.googleapis.com';

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final requestClient = _requestClientFactory();
    try {
      const mapper = GeminiMessageMapper();
      final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

      final body = <String, dynamic>{
        'contents': mapped.messages,
        'generationConfig': {'maxOutputTokens': 8192},
      };

      if (mapped.systemPrompt.isNotEmpty) {
        body['systemInstruction'] = {
          'parts': [
            {'text': mapped.systemPrompt},
          ],
        };
      }

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = const GeminiToolEncoder().encodeAll(tools);
      }

      final request = http.Request(
        'POST',
        _baseUri.resolve(
          '/$_apiVersion/models/$model:streamGenerateContent?alt=sse',
        ),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      });
      request.body = jsonEncode(body);

      final response = await requestClient.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('Gemini API error ${response.statusCode}: $errorBody');
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

  /// Parse Gemini SSE event payloads into [LlmChunk]s.
  ///
  /// Exposed as static for testability — callers feed already-decoded JSON
  /// objects (one per SSE `data:` event).
  static Stream<LlmChunk> parseStreamEvents(
    Stream<Map<String, dynamic>> events,
  ) async* {
    int inputTokens = 0;
    int outputTokens = 0;
    int callCounter = 0;

    await for (final event in events) {
      final candidates = event['candidates'];
      if (candidates is List) {
        for (final cand in candidates) {
          if (cand is! Map) continue;
          final content = cand['content'];
          if (content is! Map) continue;
          final parts = content['parts'];
          if (parts is! List) continue;

          for (final part in parts) {
            if (part is! Map) continue;
            final text = part['text'];
            if (text is String && text.isNotEmpty) {
              yield TextDelta(text);
              continue;
            }
            final fc = part['functionCall'];
            if (fc is Map) {
              final name = fc['name']?.toString() ?? '';
              final rawArgs = fc['args'];
              final args = rawArgs is Map<String, dynamic>
                  ? rawArgs
                  : (rawArgs is Map
                        ? Map<String, dynamic>.from(rawArgs)
                        : <String, dynamic>{});
              final thoughtSig =
                  (part['thoughtSignature'] ?? fc['thoughtSignature'])
                      ?.toString();
              callCounter++;
              final id = ToolCallId('gemini-call-$callCounter');
              yield ToolCallStart(id: id, name: name);
              yield ToolCallComplete(
                ToolCall(
                  id: id,
                  name: name,
                  arguments: args,
                  thoughtSignature: thoughtSig,
                ),
              );
            }
          }
        }
      }

      final usage = event['usageMetadata'];
      if (usage is Map) {
        final p = usage['promptTokenCount'];
        final c = usage['candidatesTokenCount'];
        if (p is int) inputTokens = p;
        if (c is int) outputTokens = c;
      }
    }

    yield UsageInfo(inputTokens: inputTokens, outputTokens: outputTokens);
  }
}
