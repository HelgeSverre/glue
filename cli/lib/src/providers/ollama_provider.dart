/// Native Ollama provider: adapter + NDJSON streaming client in one class.
///
/// Previously Ollama rode the OpenAI-compat adapter (`/v1/chat/completions`).
/// That worked for simple chat, but left three problems unresolved:
///
///   1. Error messages said "OpenAI API error 404" on missing Ollama models,
///      which confuses every user who sees it.
///   2. `options.num_ctx` — the fix for Ollama's silent-truncation-at-2048
///      footgun — has no place in an OpenAI-shaped body. Native /api/chat
///      takes it cleanly.
///   3. Future Ollama-specific options (`think`, `keep_alive`, model-load
///      hints) would have no home without adding branching logic into
///      the OpenAI-compat client.
///
/// Moving Ollama to its own provider keeps per-vendor quirks in per-vendor
/// files.
library;

import 'dart:async';
import 'dart:convert';

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/llm/ndjson.dart';
import 'package:glue/src/llm/tool_schema.dart';
import 'package:glue/src/providers/ollama_discovery.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

/// Hard ceiling on the `num_ctx` override Glue will send.
///
/// Keeps us from forwarding absurd context windows (some catalogue entries
/// claim 1M+) that would blow past the user's RAM budget on mid-range
/// GPUs. 128K is comfortably above every real agent conversation and
/// matches what the upstream ecosystem (Continue, Cline, opencode) settled
/// on. Exposed publicly so tests can assert it without magic-number copies.
const int ollamaNumCtxCeiling = 131072;

/// Ollama adapter + streaming client in one class.
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
class OllamaProvider extends ProviderAdapter implements LlmClient {
  OllamaProvider({
    this.model = '',
    this.systemPrompt = '',
    String baseUrl = _defaultBaseUrl,
    this.contextWindow,
    http.Client Function()? requestClientFactory,
  })  : _baseUri = Uri.parse(baseUrl),
        _requestClientFactory = requestClientFactory;

  final http.Client Function()? _requestClientFactory;
  final String model;
  final String systemPrompt;

  /// When non-null, injected as `options.num_ctx` on every request. Comes
  /// from `ModelDef.contextWindow` at adapter construction time. See class
  /// doc for why this matters.
  final int? contextWindow;

  final Uri _baseUri;

  static const _defaultBaseUrl = 'http://localhost:11434';

  // ---------- ProviderAdapter ----------

  @override
  String get adapterId => 'ollama';

  /// Ollama needs no credentials, and we don't ping the daemon at validate()
  /// time — health is surfaced through discovery (the `/model` picker) and
  /// through the eventual inference call. A stricter probe here would make
  /// startup slow and brittle.
  @override
  ProviderHealth validate(ResolvedProvider provider) => ProviderHealth.ok;

  /// Ping `GET /api/tags` to confirm the daemon is up. No auth needed, so
  /// the only failure mode is "couldn't reach it".
  @override
  Future<ProviderHealth> probe(
    ResolvedProvider provider, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final discovery = OllamaDiscovery(
      baseUrl: Uri.parse(
        _stripV1Suffix(provider.baseUrl ?? _defaultBaseUrl),
      ),
      clientFactory: _requestClientFactory,
      timeout: timeout,
    );
    return await discovery.ping()
        ? ProviderHealth.ok
        : ProviderHealth.unreachable;
  }

  @override
  bool isConnected(ProviderDef provider, CredentialStore store) => true;

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) {
    return OllamaProvider(
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: _stripV1Suffix(provider.baseUrl ?? _defaultBaseUrl),
      // Inject num_ctx when the catalog knows the model's context window.
      // Passthrough models (user-typed uncatalogued tags) get null here and
      // fall back to Ollama's default, which is the same behaviour as
      // before this adapter existed — no surprise regressions.
      contextWindow: model.def.contextWindow,
      requestClientFactory: _requestClientFactory,
    );
  }

  /// Discover locally-pulled tags. Used by the `/model` picker merge and by
  /// the pull-confirm flow; never by startup.
  @override
  Future<List<DiscoveredModel>> discoverModels(
    ResolvedProvider provider,
  ) async {
    final discovery = OllamaDiscovery(
      baseUrl: Uri.parse(
        _stripV1Suffix(provider.baseUrl ?? _defaultBaseUrl),
      ),
    );
    final installed = await discovery.listInstalled();
    return [
      for (final m in installed) DiscoveredModel(id: m.tag, name: m.tag),
    ];
  }

  /// The catalog historically stored Ollama's baseUrl with a `/v1` suffix
  /// (the OpenAI-compat path). Strip it so the native client hits
  /// `/api/chat` / `/api/tags` at the root. Accepts trailing slash too.
  static String _stripV1Suffix(String raw) {
    final trimmed = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    if (trimmed.endsWith('/v1')) {
      return trimmed.substring(0, trimmed.length - 3);
    }
    return trimmed;
  }

  // ---------- LlmClient ----------

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    // Per-request client: closing it aborts the TCP connection when the
    // stream subscription is cancelled, saving output tokens.
    final requestClient = (_requestClientFactory ?? http.Client.new)();
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
