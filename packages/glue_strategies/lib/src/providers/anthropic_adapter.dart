/// Adapter that talks to the Anthropic Messages API via [AnthropicClient].
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/anthropic_client.dart';
import 'package:glue_strategies/src/providers/provider_adapter.dart';
import 'package:glue_strategies/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

class AnthropicAdapter extends ProviderAdapter {
  AnthropicAdapter({
    this._requestClientFactory,
    this.promptCacheEnabled = true,
  });

  final http.Client Function()? _requestClientFactory;

  /// When `true`, the [AnthropicClient]s this adapter creates send the
  /// top-level `cache_control: {type: "ephemeral"}` directive that
  /// engages auto-caching. See [GlueConfig.anthropicPromptCache] for the
  /// resolution path.
  final bool promptCacheEnabled;

  @override
  String get adapterId => 'anthropic';

  @override
  ProviderHealth validate(ResolvedProvider provider) {
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
    return AnthropicClient(
      apiKey: provider.apiKey ?? '',
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: provider.baseUrl ?? 'https://api.anthropic.com',
      requestClientFactory: _requestClientFactory,
      promptCacheEnabled: promptCacheEnabled,
    );
  }
}
