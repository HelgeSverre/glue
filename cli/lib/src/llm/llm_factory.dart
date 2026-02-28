import 'package:http/http.dart' as http;

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/llm/anthropic_client.dart';
import 'package:glue/src/llm/openai_client.dart';
import 'package:glue/src/llm/ollama_client.dart';

/// Creates [LlmClient] instances from configuration.
class LlmClientFactory {
  final http.Client _httpClient;

  LlmClientFactory({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Creates an [LlmClient] for the given provider and model.
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
      LlmProvider.mistral => OpenAiClient(
          httpClient: _httpClient,
          apiKey: apiKey,
          model: model,
          systemPrompt: systemPrompt,
          baseUrl: 'https://api.mistral.ai',
        ),
      LlmProvider.ollama => OllamaClient(
          httpClient: _httpClient,
          model: model,
          systemPrompt: systemPrompt,
          baseUrl: ollamaBaseUrl,
        ),
    };
  }

  /// Creates an [LlmClient] from a [GlueConfig] using its defaults.
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

  /// Creates an [LlmClient] from a [ModelEntry] with keys from config.
  LlmClient createFromEntry(
    ModelEntry entry,
    GlueConfig config, {
    required String systemPrompt,
  }) {
    final apiKey = switch (entry.provider) {
      LlmProvider.anthropic => config.anthropicApiKey ?? '',
      LlmProvider.openai => config.openaiApiKey ?? '',
      LlmProvider.mistral => config.mistralApiKey ?? '',
      LlmProvider.ollama => '',
    };
    return create(
      provider: entry.provider,
      model: entry.modelId,
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      ollamaBaseUrl: config.ollamaBaseUrl,
    );
  }

  /// Creates an [LlmClient] from an [AgentProfile] with keys from config.
  LlmClient createFromProfile(
    AgentProfile profile,
    GlueConfig config, {
    required String systemPrompt,
  }) {
    final apiKey = switch (profile.provider) {
      LlmProvider.anthropic => config.anthropicApiKey ?? '',
      LlmProvider.openai => config.openaiApiKey ?? '',
      LlmProvider.mistral => config.mistralApiKey ?? '',
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
