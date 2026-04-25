import 'package:glue/src/boot/http.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/anthropic_provider.dart';
import 'package:glue/src/providers/copilot_provider.dart';
import 'package:glue/src/providers/ollama_provider.dart';
import 'package:glue/src/providers/openai_provider.dart';
import 'package:glue/src/providers/provider_adapter.dart';

AdapterRegistry wireProviderAdapters({
  required CredentialStore credentials,
  required HttpClientFactory httpClient,
}) {
  return AdapterRegistry([
    AnthropicProvider(requestClientFactory: () => httpClient('llm.anthropic')),
    OpenAiProvider(requestClientFactory: () => httpClient('llm.openai')),
    OllamaProvider(requestClientFactory: () => httpClient('llm.ollama')),
    CopilotProvider(
      credentialStore: credentials,
      client: httpClient('llm.copilot.auth'),
      requestClientFactory: () => httpClient('llm.copilot'),
    ),
  ]);
}
