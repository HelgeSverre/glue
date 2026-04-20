/// Adapter that talks to the Anthropic Messages API via [AnthropicClient].
library;

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/llm/anthropic_client.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

class AnthropicAdapter extends ProviderAdapter {
  AnthropicAdapter({http.Client Function()? requestClientFactory})
      : _requestClientFactory = requestClientFactory;

  final http.Client Function()? _requestClientFactory;

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
    );
  }
}
