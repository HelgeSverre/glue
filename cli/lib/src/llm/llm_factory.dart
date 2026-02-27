import 'package:http/http.dart' as http;

import '../agent/agent_core.dart';
import '../config/glue_config.dart';
import 'anthropic_client.dart';
import 'openai_client.dart';
import 'ollama_client.dart';

/// Creates [LlmClient] instances from configuration.
class LlmClientFactory {
  final http.Client _httpClient;

  LlmClientFactory({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Create an [LlmClient] for the given provider and model.
  LlmClient create({
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String systemPrompt,
    String ollamaBaseUrl = 'http://localhost:11434',
  }) {
    return switch (provider) {
      LlmProvider.anthropic => AnthropicClient(
          httpClient: _httpClient,
          apiKey: apiKey,
          model: model,
          systemPrompt: systemPrompt,
        ),
      LlmProvider.openai => OpenAiClient(
          httpClient: _httpClient,
          apiKey: apiKey,
          model: model,
          systemPrompt: systemPrompt,
        ),
      LlmProvider.ollama => OllamaClient(
          httpClient: _httpClient,
          model: model,
          systemPrompt: systemPrompt,
          baseUrl: ollamaBaseUrl,
        ),
    };
  }

  /// Create an [LlmClient] from a [GlueConfig] using its defaults.
  LlmClient createFromConfig(GlueConfig config,
      {required String systemPrompt}) {
    return create(
      provider: config.provider,
      model: config.model,
      apiKey: config.apiKey,
      systemPrompt: systemPrompt,
      ollamaBaseUrl: config.ollamaBaseUrl,
    );
  }

  /// Create an [LlmClient] from an [AgentProfile] with keys from config.
  LlmClient createFromProfile(
    AgentProfile profile,
    GlueConfig config, {
    required String systemPrompt,
  }) {
    final apiKey = switch (profile.provider) {
      LlmProvider.anthropic => config.anthropicApiKey ?? '',
      LlmProvider.openai => config.openaiApiKey ?? '',
      LlmProvider.ollama => '',
    };
    return create(
      provider: profile.provider,
      model: profile.model,
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      ollamaBaseUrl: config.ollamaBaseUrl,
    );
  }
}
