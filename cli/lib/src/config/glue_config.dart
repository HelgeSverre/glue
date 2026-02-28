import 'dart:io';
import 'package:yaml/yaml.dart';
import 'constants.dart';
import 'model_registry.dart';
import '../shell/docker_config.dart';
import '../shell/shell_config.dart';
import '../web/web_config.dart';

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
  final ShellConfig shellConfig;
  final DockerConfig dockerConfig;
  final WebConfig webConfig;

  GlueConfig({
    LlmProvider? provider,
    String? model,
    this.anthropicApiKey,
    this.openaiApiKey,
    this.ollamaBaseUrl = AppConstants.defaultOllamaBaseUrl,
    this.profiles = const {},
    this.maxSubagentDepth = AppConstants.maxSubagentDepth,
    this.bashMaxLines = AppConstants.bashMaxLinesDefault,
    ShellConfig? shellConfig,
    DockerConfig? dockerConfig,
    WebConfig? webConfig,
  })  : provider = provider ?? LlmProvider.anthropic,
        model = model ?? _defaultModel(provider ?? LlmProvider.anthropic),
        shellConfig = shellConfig ?? const ShellConfig(),
        dockerConfig = dockerConfig ?? const DockerConfig(),
        webConfig = webConfig ?? const WebConfig();

  static String _defaultModel(LlmProvider provider) =>
      ModelRegistry.defaultModelId(provider);

  /// Create a copy with selected fields replaced.
  GlueConfig copyWith({
    LlmProvider? provider,
    String? model,
  }) {
    return GlueConfig(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      anthropicApiKey: anthropicApiKey,
      openaiApiKey: openaiApiKey,
      ollamaBaseUrl: ollamaBaseUrl,
      profiles: profiles,
      maxSubagentDepth: maxSubagentDepth,
      bashMaxLines: bashMaxLines,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
    );
  }

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

    final bashMaxLines = (fileConfig?['bash'] as Map?)?['max_lines'] as int? ??
        AppConstants.bashMaxLinesDefault;

    // 2b. Resolve shell configuration.
    final shellSection = fileConfig?['shell'] as Map?;
    final shellExe = Platform.environment['GLUE_SHELL'] ??
        shellSection?['executable'] as String?;
    final shellModeStr = Platform.environment['GLUE_SHELL_MODE'] ??
        shellSection?['mode'] as String?;
    final shellMode = shellModeStr != null
        ? ShellMode.fromString(shellModeStr)
        : ShellMode.nonInteractive;
    final shellConfig = ShellConfig.detect(
      explicit: shellExe,
      shellEnv: Platform.environment['SHELL'],
      mode: shellMode,
    );

    // 2c. Resolve Docker configuration.
    final dockerSection = fileConfig?['docker'] as Map?;
    final dockerEnabled =
        Platform.environment['GLUE_DOCKER_ENABLED'] == '1' ||
            (dockerSection?['enabled'] as bool? ?? false);
    final dockerImage = Platform.environment['GLUE_DOCKER_IMAGE'] ??
        dockerSection?['image'] as String? ??
        'ubuntu:24.04';
    final dockerShell = Platform.environment['GLUE_DOCKER_SHELL'] ??
        dockerSection?['shell'] as String? ??
        'sh';
    final dockerFallback =
        dockerSection?['fallback_to_host'] as bool? ?? true;

    final dockerMounts = <MountEntry>[];
    final envMounts = Platform.environment['GLUE_DOCKER_MOUNTS'];
    if (envMounts != null && envMounts.isNotEmpty) {
      for (final spec in envMounts.split(';')) {
        if (spec.trim().isNotEmpty) {
          dockerMounts.add(MountEntry.parse(spec.trim()));
        }
      }
    }
    final fileMounts = dockerSection?['mounts'] as List?;
    if (fileMounts != null) {
      for (final m in fileMounts) {
        dockerMounts.add(MountEntry.parse(m as String));
      }
    }

    final dockerConfig = DockerConfig(
      enabled: dockerEnabled,
      image: dockerImage,
      shell: dockerShell,
      fallbackToHost: dockerFallback,
      mounts: dockerMounts,
    );

    // 2d. Resolve web configuration.
    final webSection = fileConfig?['web'] as Map?;
    final fetchSection = webSection?['fetch'] as Map?;
    final searchSection = webSection?['search'] as Map?;

    final jinaApiKey = Platform.environment['JINA_API_KEY'] ??
        fetchSection?['jina_api_key'] as String?;
    final braveApiKey = Platform.environment['BRAVE_API_KEY'] ??
        searchSection?['brave_api_key'] as String?;
    final tavilyApiKey = Platform.environment['TAVILY_API_KEY'] ??
        searchSection?['tavily_api_key'] as String?;
    final firecrawlApiKey = Platform.environment['FIRECRAWL_API_KEY'] ??
        searchSection?['firecrawl_api_key'] as String?;

    final searchProviderStr = Platform.environment['GLUE_SEARCH_PROVIDER'] ??
        searchSection?['provider'] as String?;
    final searchProvider = searchProviderStr != null
        ? WebSearchProviderType.values.firstWhere(
            (p) => p.name == searchProviderStr,
            orElse: () => WebSearchProviderType.brave,
          )
        : null;

    final webFetchConfig = WebFetchConfig(
      jinaApiKey: jinaApiKey,
      allowJinaFallback:
          fetchSection?['allow_jina_fallback'] as bool? ?? true,
      timeoutSeconds: fetchSection?['timeout_seconds'] as int? ??
          AppConstants.webFetchTimeoutSeconds,
      maxBytes: fetchSection?['max_bytes'] as int? ??
          AppConstants.webFetchMaxBytes,
      defaultMaxTokens: fetchSection?['max_tokens'] as int? ??
          AppConstants.webFetchDefaultMaxTokens,
    );

    final webSearchConfig = WebSearchConfig(
      provider: searchProvider,
      braveApiKey: braveApiKey,
      tavilyApiKey: tavilyApiKey,
      firecrawlApiKey: firecrawlApiKey,
      firecrawlBaseUrl: searchSection?['firecrawl_base_url'] as String?,
      timeoutSeconds: searchSection?['timeout_seconds'] as int? ??
          AppConstants.webSearchTimeoutSeconds,
      defaultMaxResults: searchSection?['max_results'] as int? ??
          AppConstants.webSearchDefaultMaxResults,
    );

    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
    );

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
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
    );
  }
}
