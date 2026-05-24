/// Adapter that talks to Ollama's native `/api/chat` via [OllamaClient].
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
///      `OpenAiClient`.
///
/// Moving Ollama to its own adapter + client keeps per-vendor quirks in
/// per-vendor files.
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/credentials/credential_store.dart';
import 'package:glue_strategies/src/llm/ollama_client.dart';
import 'package:glue_strategies/src/providers/ollama_discovery.dart';
import 'package:glue_strategies/src/providers/provider_adapter.dart';
import 'package:glue_strategies/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

class OllamaAdapter extends ProviderAdapter {
  OllamaAdapter({this._requestClientFactory});

  final http.Client Function()? _requestClientFactory;

  @override
  String get adapterId => 'ollama';

  /// Ollama needs no credentials, and we don't ping the daemon at validate()
  /// time — health is surfaced through discovery (the `/model` picker) and
  /// through the eventual inference call. A stricter probe here would make
  /// startup slow and brittle.
  @override
  ProviderHealth validate(ResolvedProvider provider) => ProviderHealth.ok;

  @override
  bool isConnected(ProviderDef provider, CredentialStore store) => true;

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) {
    return OllamaClient(
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: stripV1Suffix(provider.baseUrl ?? 'http://localhost:11434'),
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
        stripV1Suffix(provider.baseUrl ?? 'http://localhost:11434'),
      ),
    );
    final installed = await discovery.listInstalled();
    return [for (final m in installed) DiscoveredModel(id: m.tag, name: m.tag)];
  }
}
