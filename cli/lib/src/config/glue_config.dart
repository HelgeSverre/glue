import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/core/environment.dart';
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

/// Alias for enum-style consistency with other provider selector enums.
typedef LlmProviderType = LlmProvider;

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
  final String titleModel;
  final ShellConfig shellConfig;
  final DockerConfig dockerConfig;
  final WebConfig webConfig;
  final ObservabilityConfig observability;
  final List<String> skillPaths;
  final ApprovalMode approvalMode;

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
    this.titleModel = AppConstants.defaultTitleModel,
    ShellConfig? shellConfig,
    DockerConfig? dockerConfig,
    WebConfig? webConfig,
    this.observability = const ObservabilityConfig(),
    this.skillPaths = const [],
    this.approvalMode = ApprovalMode.confirm,
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
      titleModel: titleModel,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observability ?? this.observability,
      skillPaths: skillPaths,
      approvalMode: approvalMode,
    );
  }

  /// Validates that required configuration is present.
  void validate() {
    // Ollama runs locally — no API key needed.
    if (provider == LlmProvider.ollama) return;

    final key = apiKeyFor(provider);
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
    return apiKeyFor(provider)!;
  }

  /// API key for a specific provider (empty for Ollama).
  String? apiKeyFor(LlmProvider provider) => switch (provider) {
        LlmProvider.anthropic => anthropicApiKey,
        LlmProvider.openai => openaiApiKey,
        LlmProvider.mistral => mistralApiKey,
        LlmProvider.ollama => '',
      };

  /// Loads configuration from env vars, optional config file, and CLI overrides.
  factory GlueConfig.load({
    String? cliModel,
    Environment? environment,
    String? configPath,
  }) {
    final env = environment?.vars ?? Platform.environment;

    // 1. Load from config file.
    final configYamlPath = configPath ??
        environment?.configYamlPath ??
        '${env['HOME'] ?? '.'}/.glue/config.yaml';
    final configFile = File(configYamlPath);
    Map<String, dynamic>? fileConfig;
    if (configFile.existsSync()) {
      final content = configFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        fileConfig = Map<String, dynamic>.from(yaml);
      }
    }

    // 2. Resolve model: CLI → env → file → default.
    //    Resolve aliases (e.g. "opus" → "claude-opus-4-6") via registry.
    final rawModel =
        cliModel ?? env['GLUE_MODEL'] ?? fileConfig?['model'] as String?;

    final resolvedEntry =
        rawModel != null ? ModelRegistry.findByName(rawModel) : null;

    // 3. Resolve provider: infer from model → env → file → default.
    final providerStr =
        env['GLUE_PROVIDER'] ?? fileConfig?['provider'] as String?;

    final provider = resolvedEntry?.provider ??
        (providerStr != null
            ? LlmProvider.values.firstWhere(
                (p) => p.name == providerStr,
                orElse: () => LlmProvider.anthropic,
              )
            : LlmProvider.anthropic);

    final model = resolvedEntry?.modelId ?? rawModel ?? _defaultModel(provider);

    final anthropicKey = env['ANTHROPIC_API_KEY'] ??
        env['GLUE_ANTHROPIC_API_KEY'] ??
        (fileConfig?['anthropic'] as Map?)?['api_key'] as String?;

    final openaiKey = env['OPENAI_API_KEY'] ??
        env['GLUE_OPENAI_API_KEY'] ??
        (fileConfig?['openai'] as Map?)?['api_key'] as String?;

    final mistralKey = env['MISTRAL_API_KEY'] ??
        env['GLUE_MISTRAL_API_KEY'] ??
        (fileConfig?['mistral'] as Map?)?['api_key'] as String?;

    final ollamaBaseUrl = env['OLLAMA_BASE_URL'] ??
        env['GLUE_OLLAMA_BASE_URL'] ??
        (fileConfig?['ollama'] as Map?)?['base_url'] as String? ??
        AppConstants.defaultOllamaBaseUrl;

    final bashMaxLines = (fileConfig?['bash'] as Map?)?['max_lines'] as int? ??
        AppConstants.bashMaxLinesDefault;

    final titleModel =
        fileConfig?['title_model'] as String? ?? AppConstants.defaultTitleModel;

    // 2b. Resolve shell configuration.
    final shellSection = fileConfig?['shell'] as Map?;
    final shellExe =
        env['GLUE_SHELL'] ?? shellSection?['executable'] as String?;
    final shellModeStr =
        env['GLUE_SHELL_MODE'] ?? shellSection?['mode'] as String?;
    final shellMode = shellModeStr != null
        ? ShellMode.fromString(
            shellModeStr,
            onInvalid: (invalid) {
              stderr.writeln(
                'Warning: unknown shell mode "$invalid"; '
                'using "non_interactive".',
              );
            },
          )
        : ShellMode.nonInteractive;
    final shellConfig = ShellConfig.detect(
      explicit: shellExe,
      shellEnv: env['SHELL'],
      mode: shellMode,
    );

    // 2c. Resolve Docker configuration.
    final dockerSection = fileConfig?['docker'] as Map?;
    final dockerEnabled = env['GLUE_DOCKER_ENABLED'] == '1' ||
        (dockerSection?['enabled'] as bool? ?? false);
    final dockerImage = env['GLUE_DOCKER_IMAGE'] ??
        dockerSection?['image'] as String? ??
        'ubuntu:24.04';
    final dockerShell =
        env['GLUE_DOCKER_SHELL'] ?? dockerSection?['shell'] as String? ?? 'sh';
    final dockerFallback = dockerSection?['fallback_to_host'] as bool? ?? true;

    final dockerMounts = <MountEntry>[];
    final envMounts = env['GLUE_DOCKER_MOUNTS'];
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

    final jinaApiKey =
        env['JINA_API_KEY'] ?? fetchSection?['jina_api_key'] as String?;
    final braveApiKey =
        env['BRAVE_API_KEY'] ?? searchSection?['brave_api_key'] as String?;
    final tavilyApiKey =
        env['TAVILY_API_KEY'] ?? searchSection?['tavily_api_key'] as String?;
    final firecrawlApiKey = env['FIRECRAWL_API_KEY'] ??
        searchSection?['firecrawl_api_key'] as String?;

    final searchProviderStr =
        env['GLUE_SEARCH_PROVIDER'] ?? searchSection?['provider'] as String?;
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
    final pdfMistralApiKey =
        pdfSection?['mistral_api_key'] as String? ?? mistralKey;
    final pdfOpenaiApiKey =
        pdfSection?['openai_api_key'] as String? ?? openaiKey;
    final ocrProviderStr =
        env['GLUE_OCR_PROVIDER'] ?? pdfSection?['ocr_provider'] as String?;
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
      mistralApiKey: pdfMistralApiKey,
      openaiApiKey: pdfOpenaiApiKey,
    );

    // 2f. Resolve browser configuration.
    final browserSection = webSection?['browser'] as Map?;
    final dockerBrowserSection = browserSection?['docker'] as Map?;
    final steelSection = browserSection?['steel'] as Map?;
    final browserbaseSection = browserSection?['browserbase'] as Map?;
    final browserlessSection = browserSection?['browserless'] as Map?;

    final browserBackendStr =
        env['GLUE_BROWSER_BACKEND'] ?? browserSection?['backend'] as String?;
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
      steelApiKey: env['STEEL_API_KEY'] ?? steelSection?['api_key'] as String?,
      browserbaseApiKey: env['BROWSERBASE_API_KEY'] ??
          browserbaseSection?['api_key'] as String?,
      browserbaseProjectId: env['BROWSERBASE_PROJECT_ID'] ??
          browserbaseSection?['project_id'] as String?,
      browserlessBaseUrl: browserlessSection?['base_url'] as String?,
      browserlessApiKey: env['BROWSERLESS_API_KEY'] ??
          browserlessSection?['api_key'] as String?,
    );

    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
      pdf: pdfConfig,
      browser: browserConfig,
    );

    // 2g. Resolve observability configuration.
    final debug =
        env['GLUE_DEBUG'] == '1' || (fileConfig?['debug'] as bool? ?? false);

    final observabilityConfig = ObservabilityConfig(debug: debug);

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

    // 4. Parse approval mode.
    final approvalStr =
        env['GLUE_APPROVAL_MODE'] ?? fileConfig?['approval_mode'] as String?;
    final approvalMode = approvalStr != null
        ? ApprovalMode.values.firstWhere(
            (m) => m.name == approvalStr || m.label == approvalStr,
            orElse: () => ApprovalMode.confirm,
          )
        : ApprovalMode.confirm;

    // 5. Parse skill paths.
    final skillPaths = <String>[];
    final envSkillPaths = env['GLUE_SKILLS_PATHS'];
    if (envSkillPaths != null && envSkillPaths.isNotEmpty) {
      skillPaths.addAll(
        splitPathList(
          envSkillPaths,
          isWindows: environment?.isWindows,
        ),
      );
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
      ollamaBaseUrl: ollamaBaseUrl,
      profiles: profiles,
      bashMaxLines: bashMaxLines,
      titleModel: titleModel,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observabilityConfig,
      skillPaths: skillPaths,
      approvalMode: approvalMode,
    );
  }
}
