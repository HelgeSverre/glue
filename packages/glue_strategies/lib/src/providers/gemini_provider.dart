/// Adapter that creates [GeminiClient] instances for the Gemini Developer API.
///
/// Delegates streaming to a standalone [GeminiClient] instead of conflating
/// the adapter and client roles.
library;

import 'package:glue_core/glue_core.dart';
import 'package:glue_strategies/src/llm/gemini_client.dart';
import 'package:glue_strategies/src/providers/provider_adapter.dart';
import 'package:glue_strategies/src/providers/resolved.dart';
import 'package:http/http.dart' as http;

class GeminiProvider extends ProviderAdapter {
  GeminiProvider({this._requestClientFactory});

  final http.Client Function()? _requestClientFactory;

  static const _defaultBaseUrl = 'https://generativelanguage.googleapis.com';

  @override
  String get adapterId => 'gemini';

  @override
  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  }) {
    return GeminiClient(
      apiKey: provider.apiKey ?? '',
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: provider.baseUrl ?? _defaultBaseUrl,
      requestClientFactory: _requestClientFactory,
    );
  }
}
