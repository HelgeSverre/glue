/// Google Gemini provider: adapter + streaming `generateContent` client in one
/// class.
///
/// Talks to the Gemini Developer API (`generativelanguage.googleapis.com`).
/// Authentication is API-key only (`GEMINI_API_KEY`). Google-account login,
/// Code Assist, and Vertex AI are intentionally out of scope here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/llm/message_mapper.dart';
import 'package:glue/src/llm/sse.dart';
import 'package:glue/src/llm/tool_schema.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

/// Adapter that talks to the Gemini Developer API with streaming.
///
/// {@category LLM Providers}
class GeminiProvider extends ProviderAdapter implements LlmClient {
  GeminiProvider({
    this.apiKey = '',
    this.model = '',
    this.systemPrompt = '',
    String baseUrl = _defaultBaseUrl,
    http.Client Function()? requestClientFactory,
  })  : _baseUri = Uri.parse(baseUrl),
        _requestClientFactory = requestClientFactory;

  /// Outer HTTP factory — preserved so `createClient()` can hand it to each
  /// per-request instance it spawns.
  final http.Client Function()? _requestClientFactory;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final Uri _baseUri;

  static const _apiVersion = 'v1beta';
  static const _defaultBaseUrl = 'https://generativelanguage.googleapis.com';

  // ---------- ProviderAdapter ----------

  @override
  String get adapterId => 'gemini';

  @override
  ProviderHealth validate(ResolvedProvider provider) {
    final apiKey = provider.apiKey;
    return (apiKey != null && apiKey.isNotEmpty)
        ? ProviderHealth.ok
        : ProviderHealth.missingCredential;
  }

  /// `GET /v1beta/models` — cheapest auth-required endpoint. 200 ⇒ key works,
  /// 400/401/403 ⇒ rejected, anything else ⇒ couldn't determine.
  @override
  Future<ProviderHealth> probe(
    ResolvedProvider provider, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final apiKey = provider.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return ProviderHealth.missingCredential;
    }
    final base = Uri.parse(provider.baseUrl ?? _defaultBaseUrl);
    final uri = base.resolve('/$_apiVersion/models');
    final client = (_requestClientFactory ?? http.Client.new)();
    try {
      final response = await client
          .get(uri, headers: {'x-goog-api-key': apiKey}).timeout(timeout);
      if (response.statusCode == 200) return ProviderHealth.ok;
      // Gemini returns 400 with reason API_KEY_INVALID for bad keys, plus
      // the more typical 401/403. Treat all of those as rejected.
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        if (response.statusCode == 400 &&
            !response.body.contains('API_KEY_INVALID')) {
          return ProviderHealth.unreachable;
        }
        return ProviderHealth.unauthorized;
      }
      return ProviderHealth.unreachable;
    } on TimeoutException {
      return ProviderHealth.unreachable;
    } on SocketException {
      return ProviderHealth.unreachable;
    } on http.ClientException {
      return ProviderHealth.unreachable;
    } finally {
      client.close();
    }
  }

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) {
    return GeminiProvider(
      apiKey: provider.apiKey ?? '',
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: provider.baseUrl ?? _defaultBaseUrl,
      requestClientFactory: _requestClientFactory,
    );
  }

  // ---------- LlmClient ----------

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    final requestClient = (_requestClientFactory ?? http.Client.new)();
    try {
      const mapper = GeminiMessageMapper();
      final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

      final body = <String, dynamic>{
        'contents': mapped.messages,
        'generationConfig': {
          'maxOutputTokens': 8192,
        },
      };

      if (mapped.systemPrompt.isNotEmpty) {
        body['systemInstruction'] = {
          'parts': [
            {'text': mapped.systemPrompt}
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
        throw Exception(
          'Gemini API error ${response.statusCode}: $errorBody',
        );
      }

      yield* parseStreamEvents(
        decodeSse(response.stream).map(
          (e) => jsonDecode(e.data) as Map<String, dynamic>,
        ),
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
              callCounter++;
              final id = 'gemini-call-$callCounter';
              yield ToolCallStart(id: id, name: name);
              yield ToolCallComplete(ToolCall(
                id: id,
                name: name,
                arguments: args,
              ));
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
