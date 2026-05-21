/// One adapter for every OpenAI-shaped endpoint.
///
/// The `adapter: openai` catalog entry can point at the canonical OpenAI API,
/// Groq, Ollama, OpenRouter, vLLM, or Mistral. Per-vendor quirks live in the
/// [CompatibilityProfile] picked from [ProviderDef.compatibility] — not in
/// branching code here.
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/openai_client.dart';
import 'package:glue_strategies/src/providers/compatibility_profile.dart';
import 'package:glue_strategies/src/providers/provider_adapter.dart';
import 'package:glue_strategies/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

class OpenAiCompatibleAdapter extends ProviderAdapter {
  OpenAiCompatibleAdapter({this._requestClientFactory});

  final http.Client Function()? _requestClientFactory;

  @override
  String get adapterId => 'openai';

  @override
  ProviderHealth validate(ResolvedProvider provider) {
    if (provider.def.auth.kind == AuthKind.none) return ProviderHealth.ok;
    final apiKey = provider.apiKey;
    return (apiKey != null && apiKey.isNotEmpty)
        ? ProviderHealth.ok
        : ProviderHealth.missingCredential;
  }

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) {
    final baseUrl = provider.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw ArgumentError(
        'Provider "${provider.id}" is missing base_url. Add it to '
        '~/.glue/models.yaml (e.g. https://api.openai.com/v1). The remote '
        'catalog sanitizer strips base_url for security, so provider entries '
        'overlaid from a remote catalog must re-declare it locally.',
      );
    }
    final profile = CompatibilityProfile.fromString(provider.compatibility);
    return OpenAiClient(
      apiKey: provider.apiKey ?? '',
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: baseUrl,
      profile: profile,
      extraHeaders: provider.requestHeaders,
      requestClientFactory: _requestClientFactory,
    );
  }
}
