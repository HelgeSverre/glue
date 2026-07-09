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
import 'package:glue_strategies/src/llm/retry.dart';
import 'package:glue_strategies/src/llm/sse.dart';
import 'package:glue_strategies/src/llm/stream_request.dart';
import 'package:glue_strategies/src/llm/tool_schema.dart';
import 'package:http/http.dart' as http;

/// Gemini candidate `finishReason` values that signal an aborted/abnormal
/// completion rather than a clean stop. `STOP` (normal) and `MAX_TOKENS`
/// (legitimate length truncation) are deliberately excluded — the rest mean
/// the turn was cut short by a policy/safety filter or a malformed call, and a
/// silently-truncated turn must surface as an error instead of a clean finish.
const Set<String> _abnormalGeminiFinishReasons = {
  'SAFETY',
  'RECITATION',
  'BLOCKLIST',
  'PROHIBITED_CONTENT',
  'SPII',
  'MALFORMED_FUNCTION_CALL',
  'OTHER',
};

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
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) {
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

    return retryStream(
      () => sendAndStream(
        requestClientFactory: _requestClientFactory,
        uri: _baseUri.resolve(
          '/$_apiVersion/models/$model:streamGenerateContent?alt=sse',
        ),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: body,
        providerName: 'Gemini',
        parse: (bytes) => parseStreamEvents(
          decodeSse(
            bytes,
          ).map((e) => jsonDecode(e.data) as Map<String, dynamic>),
        ),
      ),
    );
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
      // A blocked prompt (safety/recitation filter) arrives as
      // `promptFeedback.blockReason` with no usable candidates. Surface it as
      // an error so a blocked turn does not masquerade as a clean, empty
      // success.
      final feedback = event['promptFeedback'];
      if (feedback is Map) {
        final blockReason = feedback['blockReason'];
        if (blockReason != null) {
          throw Exception('Gemini blocked the prompt: $blockReason');
        }
      }

      final candidates = event['candidates'];
      if (candidates is List) {
        for (final cand in candidates) {
          if (cand is! Map) continue;

          // Abnormal terminations (SAFETY, RECITATION, MALFORMED_FUNCTION_CALL,
          // …) truncate the turn mid-stream; checked before the content guard
          // because the terminating candidate often carries no `content`.
          final finishReason = cand['finishReason'];
          if (finishReason is String &&
              _abnormalGeminiFinishReasons.contains(finishReason)) {
            throw Exception(
              'Gemini stopped abnormally: finishReason=$finishReason',
            );
          }

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
