import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/config/permission_mode.dart';
import 'package:glue/src/shell/docker_config.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/observability/observability_config.dart';

/// Splits a path-list environment variable using platform-appropriate separators.
///
/// Unix uses `:` (like `$PATH`), Windows uses `;`.
List<String> splitPathList(String value, {bool? isWindows}) {
  final sep = (isWindows ?? Platform.isWindows) ? ';' : ':';
  return value.split(sep).where((s) => s.isNotEmpty).toList();
}

/// Supported LLM providers.
///
/// {@category Core}
enum LlmProvider { anthropic, openai, mistral, ollama }

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
  final String? mistralApiKey;
  final String ollamaBaseUrl;
  final Map<String, AgentProfile> profiles;
  final int maxSubagentDepth;
  final int bashMaxLines;
  final ShellConfig shellConfig;
  final DockerConfig dockerConfig;
  final WebConfig webConfig;
  final ObservabilityConfig observability;
  final List<String> skillPaths;
  final PermissionMode permissionMode;

  GlueConfig({
    LlmProvider? provider,
    String? model,
    this.anthropicApiKey,
    this.openaiApiKey,
    this.mistralApiKey,
    this.ollamaBaseUrl = AppConstants.defaultOllamaBaseUrl,
    this.profiles = const {},
    this.maxSubagentDepth = AppConstants.maxSubagentDepth,
    this.bashMaxLines = AppConstants.bashMaxLinesDefault,
    ShellConfig? shellConfig,
    DockerConfig? dockerConfig,
    WebConfig? webConfig,
    this.observability = const ObservabilityConfig(),
    this.skillPaths = const [],
    this.permissionMode = PermissionMode.confirm,
  })  : provider = provider ?? LlmProvider.anthropic,
        model = model ?? _defaultModel(provider ?? LlmProvider.anthropic),
        shellConfig = shellConfig ?? const ShellConfig(),
        dockerConfig = dockerConfig ?? const DockerConfig(),
        webConfig = webConfig ?? const WebConfig();

  static String _defaultModel(LlmProvider provider) =>
      ModelRegistry.defaultModelId(provider);

  /// Creates a copy with selected fields replaced.
  GlueConfig copyWith({
    LlmProvider? provider,
    String? model,
    ObservabilityConfig? observability,
  }) {
    return GlueConfig(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      anthropicApiKey: anthropicApiKey,
      openaiApiKey: openaiApiKey,
      mistralApiKey: mistralApiKey,
      ollamaBaseUrl: ollamaBaseUrl,
      profiles: profiles,
      maxSubagentDepth: maxSubagentDepth,
      bashMaxLines: bashMaxLines,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observability ?? this.observability,
    );
  }

  /// Validates that required configuration is present.
  void validate() {
    // Ollama runs locally — no API key needed.
    if (provider == LlmProvider.ollama) return;

    final key = switch (provider) {
      LlmProvider.anthropic => anthropicApiKey,
      LlmProvider.openai => openaiApiKey,
      LlmProvider.mistral => mistralApiKey,
      LlmProvider.ollama => '', // unreachable
    };
    if (key == null || key.isEmpty) {
      final envVar = switch (provider) {
        LlmProvider.anthropic => 'ANTHROPIC_API_KEY',
        LlmProvider.openai => 'OPENAI_API_KEY',
        LlmProvider.mistral => 'MISTRAL_API_KEY',
        LlmProvider.ollama => '',
      };
      throw ConfigError(
        'Missing API key for provider ${provider.name}. '
        'Set $envVar or add it to ~/.glue/config.yaml',
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
      LlmProvider.mistral => mistralApiKey!,
      LlmProvider.ollama => '',
    };
  }

  /// Loads configuration from env vars, optional config file, and CLI overrides.
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

    final mistralKey = Platform.environment['MISTRAL_API_KEY'] ??
        Platform.environment['GLUE_MISTRAL_API_KEY'] ??
        (fileConfig?['mistral'] as Map?)?['api_key'] as String?;

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
    final dockerEnabled = Platform.environment['GLUE_DOCKER_ENABLED'] == '1' ||
        (dockerSection?['enabled'] as bool? ?? false);
    final dockerImage = Platform.environment['GLUE_DOCKER_IMAGE'] ??
        dockerSection?['image'] as String? ??
        'ubuntu:24.04';
    final dockerShell = Platform.environment['GLUE_DOCKER_SHELL'] ??
        dockerSection?['shell'] as String? ??
        'sh';
    final dockerFallback = dockerSection?['fallback_to_host'] as bool? ?? true;

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
      allowJinaFallback: fetchSection?['allow_jina_fallback'] as bool? ?? true,
      timeoutSeconds: fetchSection?['timeout_seconds'] as int? ??
          AppConstants.webFetchTimeoutSeconds,
      maxBytes:
          fetchSection?['max_bytes'] as int? ?? AppConstants.webFetchMaxBytes,
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

    // 2e. Resolve PDF configuration.
    final pdfSection = webSection?['pdf'] as Map?;
    final mistralApiKey = Platform.environment['MISTRAL_API_KEY'] ??
        pdfSection?['mistral_api_key'] as String?;
    final pdfOpenaiApiKey = Platform.environment['OPENAI_API_KEY'] ??
        pdfSection?['openai_api_key'] as String?;
    final ocrProviderStr = Platform.environment['GLUE_OCR_PROVIDER'] ??
        pdfSection?['ocr_provider'] as String?;
    final ocrProvider = ocrProviderStr != null
        ? OcrProviderType.values.firstWhere(
            (p) => p.name == ocrProviderStr,
            orElse: () => OcrProviderType.mistral,
          )
        : OcrProviderType.mistral;

    final pdfConfig = PdfConfig(
      maxBytes: pdfSection?['max_bytes'] as int? ?? AppConstants.pdfMaxBytes,
      timeoutSeconds: pdfSection?['timeout_seconds'] as int? ??
          AppConstants.pdfTimeoutSeconds,
      enableOcrFallback: pdfSection?['enable_ocr_fallback'] as bool? ?? true,
      ocrProvider: ocrProvider,
      mistralApiKey: mistralApiKey,
      openaiApiKey: pdfOpenaiApiKey,
    );

    // 2f. Resolve browser configuration.
    final browserSection = webSection?['browser'] as Map?;
    final dockerBrowserSection = browserSection?['docker'] as Map?;
    final steelSection = browserSection?['steel'] as Map?;
    final browserbaseSection = browserSection?['browserbase'] as Map?;
    final browserlessSection = browserSection?['browserless'] as Map?;

    final browserBackendStr = Platform.environment['GLUE_BROWSER_BACKEND'] ??
        browserSection?['backend'] as String?;
    final browserBackend = browserBackendStr != null
        ? BrowserBackend.values.firstWhere(
            (b) => b.name == browserBackendStr,
            orElse: () => BrowserBackend.local,
          )
        : BrowserBackend.local;

    final browserConfig = BrowserConfig(
      backend: browserBackend,
      headed: browserSection?['headed'] as bool? ?? false,
      dockerImage: dockerBrowserSection?['image'] as String? ??
          AppConstants.browserDockerImage,
      dockerPort: dockerBrowserSection?['port'] as int? ??
          AppConstants.browserDockerPort,
      steelApiKey: Platform.environment['STEEL_API_KEY'] ??
          steelSection?['api_key'] as String?,
      browserbaseApiKey: Platform.environment['BROWSERBASE_API_KEY'] ??
          browserbaseSection?['api_key'] as String?,
      browserbaseProjectId: Platform.environment['BROWSERBASE_PROJECT_ID'] ??
          browserbaseSection?['project_id'] as String?,
      browserlessBaseUrl: browserlessSection?['base_url'] as String?,
      browserlessApiKey: Platform.environment['BROWSERLESS_API_KEY'] ??
          browserlessSection?['api_key'] as String?,
    );

    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
      pdf: pdfConfig,
      browser: browserConfig,
    );

    // 2g. Resolve observability configuration.
    final debug = Platform.environment['GLUE_DEBUG'] == '1' ||
        (fileConfig?['debug'] as bool? ?? false);

    final telemetrySection = fileConfig?['telemetry'] as Map?;
    final langfuseSection = telemetrySection?['langfuse'] as Map?;
    final otelSection = telemetrySection?['otel'] as Map?;
    final flushInterval =
        telemetrySection?['flush_interval_seconds'] as int? ?? 30;

    final langfuseConfig = LangfuseConfig(
      enabled: langfuseSection?['enabled'] as bool? ?? false,
      baseUrl: Platform.environment['LANGFUSE_BASE_URL'] ??
          langfuseSection?['base_url'] as String?,
      publicKey: Platform.environment['LANGFUSE_PUBLIC_KEY'] ??
          langfuseSection?['public_key'] as String?,
      secretKey: Platform.environment['LANGFUSE_SECRET_KEY'] ??
          langfuseSection?['secret_key'] as String?,
    );

    final otelEndpoint = Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ??
        otelSection?['endpoint'] as String?;
    final otelHeadersEnv = Platform.environment['OTEL_EXPORTER_OTLP_HEADERS'];
    final otelHeaders = <String, String>{};
    if (otelHeadersEnv != null && otelHeadersEnv.isNotEmpty) {
      for (final pair in otelHeadersEnv.split(',')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          otelHeaders[pair.substring(0, idx).trim()] =
              pair.substring(idx + 1).trim();
        }
      }
    } else if (otelSection?['headers'] is Map) {
      final h = otelSection!['headers'] as Map;
      for (final e in h.entries) {
        otelHeaders[e.key as String] = e.value as String;
      }
    }

    final otelConfig = OtelConfig(
      enabled: otelSection?['enabled'] as bool? ?? false,
      endpoint: otelEndpoint,
      headers: otelHeaders,
    );

    final observabilityConfig = ObservabilityConfig(
      debug: debug,
      langfuse: langfuseConfig,
      otel: otelConfig,
      flushIntervalSeconds: flushInterval,
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

    // 4. Parse permission mode.
    final permModeStr = Platform.environment['GLUE_PERMISSION_MODE'] ??
        fileConfig?['permission_mode'] as String?;
    final permissionMode = permModeStr != null
        ? PermissionMode.values.firstWhere(
            (m) => m.name == permModeStr || m.label == permModeStr,
            orElse: () => PermissionMode.confirm,
          )
        : PermissionMode.confirm;

    // 5. Parse skill paths.
    final skillPaths = <String>[];
    final envSkillPaths = Platform.environment['GLUE_SKILLS_PATHS'];
    if (envSkillPaths != null && envSkillPaths.isNotEmpty) {
      skillPaths.addAll(splitPathList(envSkillPaths));
    }
    final skillsSection = fileConfig?['skills'] as Map?;
    final fileSkillPaths = skillsSection?['paths'] as List?;
    if (fileSkillPaths != null) {
      skillPaths.addAll(fileSkillPaths.cast<String>());
    }

    return GlueConfig(
      provider: provider,
      model: model,
      anthropicApiKey: anthropicKey,
      openaiApiKey: openaiKey,
      mistralApiKey: mistralKey,
      profiles: profiles,
      bashMaxLines: bashMaxLines,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observabilityConfig,
      skillPaths: skillPaths,
      permissionMode: permissionMode,
    );
  }
}
