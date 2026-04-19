/// One adapter for every OpenAI-shaped endpoint.
///
/// The `adapter: openai` catalog entry can point at the canonical OpenAI API,
/// Groq, Ollama, OpenRouter, vLLM, or Mistral. Per-vendor quirks live in the
/// [CompatibilityProfile] picked from [ProviderDef.compatibility] — not in
/// branching code here.
library;

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/llm/openai_client.dart';
import 'package:glue/src/providers/compatibility_profile.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';

class OpenAiCompatibleAdapter extends ProviderAdapter {
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
    final profile = CompatibilityProfile.fromString(provider.compatibility);
    return OpenAiClient(
      apiKey: provider.apiKey ?? '',
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: provider.baseUrl ?? 'https://api.openai.com',
      profile: profile,
      extraHeaders: provider.requestHeaders,
    );
  }
}
