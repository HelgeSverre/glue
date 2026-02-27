import 'dart:io';
import 'package:yaml/yaml.dart';

/// Supported LLM providers.
enum LlmProvider { anthropic, openai, ollama }

/// An agent profile specifying provider and model for a particular role.
class AgentProfile {
  final LlmProvider provider;
  final String model;

  const AgentProfile({required this.provider, required this.model});

  @override
  String toString() => 'AgentProfile($provider, $model)';
}

/// Error thrown when configuration is invalid.
class ConfigError implements Exception {
  final String message;
  ConfigError(this.message);

  @override
  String toString() => 'ConfigError: $message';
}

/// Glue application configuration.
///
/// Resolution order: CLI args → env vars → config file → defaults.
class GlueConfig {
  final LlmProvider provider;
  final String model;
  final String? anthropicApiKey;
  final String? openaiApiKey;
  final String ollamaBaseUrl;
  final Map<String, AgentProfile> profiles;
  final int maxSubagentDepth;
  final int bashMaxLines;

  GlueConfig({
    LlmProvider? provider,
    String? model,
    this.anthropicApiKey,
    this.openaiApiKey,
    this.ollamaBaseUrl = 'http://localhost:11434',
    this.profiles = const {},
    this.maxSubagentDepth = 2,
    this.bashMaxLines = 50,
  })  : provider = provider ?? LlmProvider.anthropic,
        model = model ?? _defaultModel(provider ?? LlmProvider.anthropic);

  static String _defaultModel(LlmProvider provider) => switch (provider) {
        LlmProvider.anthropic => 'claude-sonnet-4-6',
        LlmProvider.openai => 'gpt-4.1',
        LlmProvider.ollama => 'llama3.2',
      };

  /// Validate that required configuration is present.
  void validate() {
    // Ollama runs locally — no API key needed.
    if (provider == LlmProvider.ollama) return;

    final key = switch (provider) {
      LlmProvider.anthropic => anthropicApiKey,
      LlmProvider.openai => openaiApiKey,
      LlmProvider.ollama => '', // unreachable
    };
    if (key == null || key.isEmpty) {
      throw ConfigError(
        'Missing API key for provider ${provider.name}. '
        'Set ${provider == LlmProvider.anthropic ? "ANTHROPIC_API_KEY" : "OPENAI_API_KEY"} '
        'or add it to ~/.glue/config.yaml',
      );
    }
  }

  /// API key for the currently selected provider (empty for Ollama).
  String get apiKey {
    if (provider == LlmProvider.ollama) return '';
    validate();
    return switch (provider) {
      LlmProvider.anthropic => anthropicApiKey!,
      LlmProvider.openai => openaiApiKey!,
      LlmProvider.ollama => '',
    };
  }

  /// Load configuration from env vars, optional config file, and CLI overrides.
  factory GlueConfig.load({
    String? cliProvider,
    String? cliModel,
  }) {
    // 1. Load from config file.
    final configFile = File(
      '${Platform.environment['HOME'] ?? '.'}/.glue/config.yaml',
    );
    Map<String, dynamic>? fileConfig;
    if (configFile.existsSync()) {
      final content = configFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        fileConfig = Map<String, dynamic>.from(yaml);
      }
    }

    // 2. Resolve values: CLI → env → file → defaults.
    final providerStr = cliProvider ??
        Platform.environment['GLUE_PROVIDER'] ??
        fileConfig?['provider'] as String?;

    final provider = providerStr != null
        ? LlmProvider.values.firstWhere(
            (p) => p.name == providerStr,
            orElse: () => LlmProvider.anthropic,
          )
        : LlmProvider.anthropic;

    final model = cliModel ??
        Platform.environment['GLUE_MODEL'] ??
        fileConfig?['model'] as String? ??
        _defaultModel(provider);

    final anthropicKey = Platform.environment['ANTHROPIC_API_KEY'] ??
        Platform.environment['GLUE_ANTHROPIC_API_KEY'] ??
        (fileConfig?['anthropic'] as Map?)?['api_key'] as String?;

    final openaiKey = Platform.environment['OPENAI_API_KEY'] ??
        Platform.environment['GLUE_OPENAI_API_KEY'] ??
        (fileConfig?['openai'] as Map?)?['api_key'] as String?;

    final bashMaxLines = (fileConfig?['bash'] as Map?)?['max_lines'] as int? ?? 50;

    // 3. Parse profiles.
    final profiles = <String, AgentProfile>{};
    final profilesYaml = fileConfig?['profiles'] as Map?;
    if (profilesYaml != null) {
      for (final entry in profilesYaml.entries) {
        final name = entry.key as String;
        final val = entry.value as Map;
        profiles[name] = AgentProfile(
          provider: LlmProvider.values.firstWhere(
            (p) => p.name == (val['provider'] as String? ?? 'anthropic'),
          ),
          model: val['model'] as String? ?? _defaultModel(provider),
        );
      }
    }

    return GlueConfig(
      provider: provider,
      model: model,
      anthropicApiKey: anthropicKey,
      openaiApiKey: openaiKey,
      profiles: profiles,
      bashMaxLines: bashMaxLines,
    );
  }
}
