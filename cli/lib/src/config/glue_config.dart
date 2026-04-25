import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:glue/src/catalog/catalog_loader.dart';
import 'package:glue/src/catalog/catalog_parser.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';
import 'package:glue/src/catalog/model_resolver.dart';
import 'package:glue/src/catalog/models_generated.dart';
import 'package:glue/src/config/approval_mode.dart';
import 'package:glue/src/config/constants.dart';
import 'package:glue/src/context/context_config.dart';
import 'package:glue/src/core/environment.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/observability/observability_config.dart';
import 'package:glue/src/providers/anthropic_provider.dart';
import 'package:glue/src/providers/copilot_provider.dart';
import 'package:glue/src/providers/ollama_provider.dart';
import 'package:glue/src/providers/openai_provider.dart';
import 'package:glue/src/providers/provider_adapter.dart';
import 'package:glue/src/providers/resolved.dart';
import 'package:glue/src/shell/docker_config.dart';
import 'package:glue/src/shell/shell_config.dart';
import 'package:glue/src/web/browser/browser_config.dart';
import 'package:glue/src/web/web_config.dart';
import 'package:glue/src/utils.dart';

/// Splits a path-list env var using platform-appropriate separators.
/// Unix uses `:` (like `$PATH`), Windows uses `;`.
List<String> splitPathList(String value, {bool? isWindows}) {
  final sep = (isWindows ?? Platform.isWindows) ? ';' : ':';
  return value.split(sep).where((s) => s.isNotEmpty).toList();
}

/// Configuration for how Glue sources the bundled/remote model catalog.
class CatalogSourceConfig {
  const CatalogSourceConfig({
    this.refresh = 'manual',
    this.remoteUrl,
  });

  /// `never | manual | daily | startup`. See `docs/reference/models.yaml`.
  final String refresh;

  /// When non-null, background refresh pulls from here.
  final Uri? remoteUrl;
}

class ConfigError implements Exception {
  ConfigError(this.message);
  final String message;

  @override
  String toString() => 'ConfigError: $message';
}

/// Glue application configuration.
///
/// Resolution order for the active model: CLI args → env vars
/// (`GLUE_MODEL`) → `~/.glue/config.yaml` → catalog defaults.
///
/// Credentials (API keys) live *outside* this object — in environment
/// variables and `~/.glue/credentials.json`, accessed via [credentials].
class GlueConfig {
  GlueConfig({
    required this.activeModel,
    required this.catalogData,
    required this.credentials,
    required this.adapters,
    this.smallModel,
    this.profiles = const {},
    this.catalog = const CatalogSourceConfig(),
    this.maxSubagentDepth = AppConstants.maxSubagentDepth,
    this.bashMaxLines = AppConstants.bashMaxLinesDefault,
    ShellConfig? shellConfig,
    DockerConfig? dockerConfig,
    WebConfig? webConfig,
    this.observability = const ObservabilityConfig(),
    this.contextConfig = const ContextConfig(),
    this.skillPaths = const [],
    this.approvalMode = ApprovalMode.confirm,
    this.titleGenerationEnabled = true,
  })  : shellConfig = shellConfig ?? const ShellConfig(),
        dockerConfig = dockerConfig ?? const DockerConfig(),
        webConfig = webConfig ?? const WebConfig();

  /// Primary model used for agent conversations.
  final ModelRef activeModel;

  /// Cheap/fast model for session title generation, summaries, etc.
  /// When null, [activeModel] is used.
  final ModelRef? smallModel;

  /// Named shortcuts (`/model @fast`, etc.).
  final Map<String, ModelRef> profiles;

  final CatalogSourceConfig catalog;

  /// The fully-merged model catalog (bundled + cached remote + local).
  final ModelCatalog catalogData;

  /// Resolves [CredentialRef]s and walks [AuthSpec] for providers.
  final CredentialStore credentials;

  /// Registry of provider adapters (anthropic, openai-compatible, …).
  ///
  /// Not final — boot wiring swaps this after observability is constructed
  /// so adapters can thread a logging HTTP factory into their LLM clients.
  AdapterRegistry adapters;

  final int maxSubagentDepth;
  final int bashMaxLines;
  final ShellConfig shellConfig;
  final DockerConfig dockerConfig;
  final WebConfig webConfig;
  final ObservabilityConfig observability;

  /// Context-window management configuration.
  final ContextConfig contextConfig;

  final List<String> skillPaths;
  final ApprovalMode approvalMode;

  /// When `false`, session title generation is skipped entirely. No LLM
  /// client is created and the session title remains `null`.
  ///
  /// Resolution order: `GLUE_TITLE_GENERATION_ENABLED` env var →
  /// `title_generation_enabled` YAML key → default `true`.
  final bool titleGenerationEnabled;

  /// Resolve [ref] against the loaded catalog and credential store.
  ///
  /// Throws [ConfigError] when the provider is unknown.
  ResolvedProvider resolveProvider(ModelRef ref) =>
      resolveProviderById(ref.providerId);

  /// Resolve a provider without requiring a model id — useful for health
  /// checks and action menus where no particular model is in play.
  ResolvedProvider resolveProviderById(String providerId) {
    final def = catalogData.providers[providerId];
    if (def == null) {
      throw ConfigError(
        'unknown provider "$providerId". '
        'Available: ${catalogData.providers.keys.join(", ")}.',
      );
    }
    return ResolvedProvider(
      def: def,
      apiKey: credentials.resolveForProvider(def),
      credentials: credentials.getFields(def.id),
    );
  }

  /// Resolve [ref] to a concrete [ResolvedModel]. If the model id is not in
  /// the catalog, a synthetic [ModelDef] is returned (covers user-typed ids
  /// that provider APIs accept but we haven't catalogued).
  ResolvedModel resolveModel(ModelRef ref) {
    final provider = catalogData.providers[ref.providerId];
    if (provider == null) {
      throw ConfigError('unknown provider "${ref.providerId}"');
    }
    final def = provider.models[ref.modelId] ??
        ModelDef(id: ref.modelId, name: ref.modelId);
    return ResolvedModel(def: def, provider: provider);
  }

  /// Validates that the active model's provider has a usable credential.
  /// Throws [ConfigError] with a remediation message on failure.
  void validate() {
    final resolved = resolveProvider(activeModel);
    final adapter = adapters.lookup(resolved.adapter);
    if (adapter == null) {
      throw ConfigError(
        'no adapter registered for wire protocol '
        '"${resolved.adapter}" (provider "${resolved.id}").',
      );
    }
    final health = adapter.validate(resolved);
    switch (health) {
      case ProviderHealth.ok:
        return;
      case ProviderHealth.unknownAdapter:
        throw ConfigError(
          'adapter "${resolved.adapter}" failed validation for '
          'provider "${resolved.id}".',
        );
      case ProviderHealth.missingCredential:
        final auth = resolved.def.auth;
        final envHint = auth.kind == AuthKind.apiKey && auth.envVar != null
            ? ' or set \$${auth.envVar}'
            : '';
        throw ConfigError(
          'Not connected to "${resolved.id}". '
          'Run /provider add ${resolved.id}$envHint.',
        );
    }
  }

  GlueConfig copyWith({
    ModelRef? activeModel,
    ObservabilityConfig? observability,
    ContextConfig? contextConfig,
  }) {
    return GlueConfig(
      activeModel: activeModel ?? this.activeModel,
      smallModel: smallModel,
      profiles: profiles,
      catalog: catalog,
      catalogData: catalogData,
      credentials: credentials,
      adapters: adapters,
      maxSubagentDepth: maxSubagentDepth, // TODO: remove
      bashMaxLines: bashMaxLines, // TODO: remove
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observability ?? this.observability,
      contextConfig: contextConfig ?? this.contextConfig,
      skillPaths: skillPaths,
      approvalMode: approvalMode,
      titleGenerationEnabled: titleGenerationEnabled,
    );
  }

  /// Loads configuration from env, optional `~/.glue/config.yaml`, and CLI
  /// overrides. Constructs the merged catalog, credential store, and
  /// adapter registry.
  ///
  /// Throws [ConfigError] with a migration pointer when the config file is
  /// in the legacy v1 shape (top-level `provider:`, per-provider `api_key:`).
  factory GlueConfig.load({
    String? cliModel,
    Environment? environment,
    String? configPath,
    ModelCatalog? catalogOverride,
    CredentialStore? credentialsOverride,
    AdapterRegistry? adaptersOverride,
  }) {
    // TODO: make neat wrapper DotEnv.getOr() etc
    final env = environment?.vars ?? Platform.environment;
    final home = env['HOME'] ?? '.';

    final configYamlPath =
        configPath ?? environment?.configYamlPath ?? '$home/.glue/config.yaml';
    final configFile = File(configYamlPath);
    Map<String, dynamic>? fileConfig;
    if (configFile.existsSync()) {
      final content = configFile.readAsStringSync();
      final yaml = loadYaml(content);
      if (yaml is YamlMap) {
        fileConfig = Map<String, dynamic>.from(yaml);
      }
    }

    // Reject legacy v1 shape with a migration message.
    if (fileConfig != null) _rejectLegacyConfig(fileConfig, configYamlPath);

    // Catalog: bundled → optional cached remote → optional local overrides.
    final catalog = catalogOverride ??
        loadCatalog(
          bundled: bundledCatalog,
          cachedRemote: _loadOptionalYaml(
            env['GLUE_CATALOG_CACHE'] ??
                '${environment?.cacheDir ?? p.join(home, '.glue/cache')}/models.yaml',
          ),
          localOverrides: _loadOptionalYaml(
            '${environment?.glueDir ?? p.join(home, '.glue')}/models.yaml',
          ),
        );

    final credentials = credentialsOverride ??
        CredentialStore(
          path:
              '${environment?.glueDir ?? p.join(home, '.glue')}/credentials.json',
          env: Map<String, String>.from(env),
        );

    final adapters = adaptersOverride ??
        AdapterRegistry([
          AnthropicProvider(),
          OpenAiProvider(),
          OllamaProvider(),
          CopilotProvider(credentialStore: credentials),
        ]);

    // Resolve active model: CLI flag → GLUE_MODEL → config file → catalog default.
    final rawActive = cliModel ??
        env['GLUE_MODEL'] ??
        fileConfig?['active_model'] as String? ??
        catalog.defaults.model;
    final activeModel = _resolveModelRef(rawActive, catalog);

    final rawSmall =
        fileConfig?['small_model'] as String? ?? catalog.defaults.smallModel;
    final smallModel =
        rawSmall != null ? _resolveModelRef(rawSmall, catalog) : null;

    // Catalog source section.
    final catalogSection = fileConfig?['catalog'] as Map?;
    final catalogConfig = CatalogSourceConfig(
      refresh: catalogSection?['refresh'] as String? ?? 'manual',
      remoteUrl: (catalogSection?['remote_url'] as String?) != null
          ? Uri.parse(catalogSection!['remote_url'] as String)
          : null,
    );

    // Profiles: Map<String, ModelRef>.
    final profiles = <String, ModelRef>{};
    final profilesYaml = fileConfig?['profiles'] as Map?;
    if (profilesYaml != null) {
      for (final entry in profilesYaml.entries) {
        final name = entry.key.toString();
        final raw = entry.value.toString();
        profiles[name] = _resolveModelRef(raw, catalog);
      }
    }

    // --- non-model-related config (kept intact) ---

    final bashMaxLines = (fileConfig?['bash'] as Map?)?['max_lines'] as int? ??
        AppConstants.bashMaxLinesDefault;

    // Shell config.
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
                'Warning: unknown shell mode "$invalid"; using "non_interactive".',
              );
            },
          )
        : ShellMode.nonInteractive;
    final shellConfig = ShellConfig.detect(
      explicit: shellExe,
      shellEnv: env['SHELL'],
      mode: shellMode,
    );

    // Docker config.
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

    // Web config.
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

    // PDF uses the OpenAI/Mistral adapter's credentials when available.
    final pdfSection = webSection?['pdf'] as Map?;
    final mistralProvider = catalog.providers['mistral'];
    final openaiProvider = catalog.providers['openai'];
    final pdfMistralApiKey = pdfSection?['mistral_api_key'] as String? ??
        (mistralProvider != null
            ? credentials.resolveForProvider(mistralProvider)
            : null);
    final pdfOpenaiApiKey = pdfSection?['openai_api_key'] as String? ??
        (openaiProvider != null
            ? credentials.resolveForProvider(openaiProvider)
            : null);
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

    // Browser config (unchanged).
    final browserSection = webSection?['browser'] as Map?;
    final dockerBrowserSection = browserSection?['docker'] as Map?;
    final steelSection = browserSection?['steel'] as Map?;
    final browserbaseSection = browserSection?['browserbase'] as Map?;
    final browserlessSection = browserSection?['browserless'] as Map?;
    final anchorSection = browserSection?['anchor'] as Map?;
    final hyperbrowserSection = browserSection?['hyperbrowser'] as Map?;

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
      anchorApiKey: env['ANCHOR_API_KEY'] ??
          anchorSection?['api_key'] as String? ??
          browserSection?['anchor_api_key'] as String?,
      hyperbrowserApiKey: env['HYPERBROWSER_API_KEY'] ??
          hyperbrowserSection?['api_key'] as String? ??
          browserSection?['hyperbrowser_api_key'] as String?,
    );

    final webConfig = WebConfig(
      fetch: webFetchConfig,
      search: webSearchConfig,
      pdf: pdfConfig,
      browser: browserConfig,
    );

    // Observability.
    final observabilitySection =
        fileConfig?['observability'] as Map<dynamic, dynamic>?;
    final debug = env['GLUE_DEBUG'] == '1' ||
        (observabilitySection?['debug'] as bool? ??
            fileConfig?['debug'] as bool? ??
            false);
    final maxBodyBytes =
        (observabilitySection?['max_body_bytes'] as int?) ?? 64.kilobytes;
    final redact = (observabilitySection?['redact'] as bool?) ?? true;
    final otelSection = observabilitySection?['otel'] as Map?;
    final otelEndpoint = otelSection?['endpoint'] as String? ??
        env['OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'] ??
        env['OTEL_EXPORTER_OTLP_ENDPOINT'] ??
        env['PHOENIX_COLLECTOR_ENDPOINT'];
    final otelHeaders = _resolveOtelHeaders(otelSection, env);
    final otelResourceAttributes =
        _resolveOtelResourceAttributes(otelSection, env);
    final phoenixProject = env['PHOENIX_PROJECT_NAME'];
    if (phoenixProject != null && phoenixProject.isNotEmpty) {
      otelResourceAttributes.putIfAbsent(
        'openinference.project.name',
        () => phoenixProject,
      );
    }
    otelResourceAttributes.putIfAbsent(
      'openinference.project.name',
      () => 'glue',
    );
    final otelProtocol = OtelProtocol.parse(
      otelSection?['protocol'] as String? ?? env['OTEL_EXPORTER_OTLP_PROTOCOL'],
    );
    final otelConfig = OtelConfig(
      enabled: otelSection?['enabled'] as bool? ??
          _envBool(env['OTEL_SDK_DISABLED']) != true &&
              otelEndpoint != null &&
              otelEndpoint.isNotEmpty,
      endpoint: otelEndpoint,
      headers: otelHeaders,
      serviceName: otelSection?['service_name'] as String? ??
          env['OTEL_SERVICE_NAME'] ??
          'glue',
      resourceAttributes: otelResourceAttributes,
      timeoutMilliseconds:
          otelSection?['timeout_milliseconds'] as int? ?? 10000,
      protocol: otelProtocol,
    );
    final observabilityConfig = ObservabilityConfig(
      debug: debug,
      maxBodyBytes: maxBodyBytes,
      redact: redact,
      otel: otelConfig,
    );

    // Approval mode.
    final approvalStr =
        env['GLUE_APPROVAL_MODE'] ?? fileConfig?['approval_mode'] as String?;
    final approvalMode = approvalStr != null
        ? ApprovalMode.values.firstWhere(
            (m) => m.name == approvalStr || m.label == approvalStr,
            orElse: () => ApprovalMode.confirm,
          )
        : ApprovalMode.confirm;

    // Title generation toggle. Env wins over YAML; default enabled.
    final titleEnabledEnv = env['GLUE_TITLE_GENERATION_ENABLED'];
    final titleEnabledYaml = fileConfig?['title_generation_enabled'] as bool?;
    final titleGenerationEnabled = titleEnabledEnv != null
        ? (titleEnabledEnv.toLowerCase() == 'true' || titleEnabledEnv == '1')
        : (titleEnabledYaml ?? true);

    // Skill paths.
    final skillPaths = <String>[];
    final envSkillPaths = env['GLUE_SKILLS_PATHS'];
    if (envSkillPaths != null && envSkillPaths.isNotEmpty) {
      skillPaths.addAll(
        splitPathList(envSkillPaths, isWindows: environment?.isWindows),
      );
    }
    final skillsSection = fileConfig?['skills'] as Map?;
    final fileSkillPaths = skillsSection?['paths'] as List?;
    if (fileSkillPaths != null) {
      skillPaths.addAll(fileSkillPaths.cast<String>());
    }

    // Context-window management config.
    final contextSection = fileConfig?['context'] as Map?;
    final contextConfig = ContextConfig(
      autoCompact: contextSection?['auto_compact'] as bool? ?? true,
      compactThreshold:
          (contextSection?['compact_threshold'] as num?)?.toDouble() ?? 0.80,
      criticalThreshold:
          (contextSection?['critical_threshold'] as num?)?.toDouble() ?? 0.95,
      keepRecentTurns: contextSection?['keep_recent_turns'] as int? ?? 4,
      toolResultTrimAfter:
          contextSection?['tool_result_trim_after'] as int? ?? 3,
    );

    return GlueConfig(
      activeModel: activeModel,
      smallModel: smallModel,
      profiles: profiles,
      catalog: catalogConfig,
      catalogData: catalog,
      credentials: credentials,
      adapters: adapters,
      bashMaxLines: bashMaxLines,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observabilityConfig,
      contextConfig: contextConfig,
      skillPaths: skillPaths,
      approvalMode: approvalMode,
      titleGenerationEnabled: titleGenerationEnabled,
    );
  }
}

/// Resolve a user-typed model identifier against the catalog.
///
/// Explicit `<provider>/<id>` is never fuzzy-matched — catalogued inputs
/// return the catalog entry, uncatalogued inputs pass through verbatim.
/// Bare inputs require an exact match; substring fallback is gone because
/// it silently rewrote `gemma4` into `gemma4:26b`. See [resolveModelInput].
ModelRef _resolveModelRef(String raw, ModelCatalog catalog) {
  final outcome = resolveModelInput(raw, catalog);
  switch (outcome) {
    case ResolvedExact():
      return outcome.ref;
    case ResolvedPassthrough():
      if (!outcome.providerKnown) {
        throw ConfigError(
          'unknown provider "${outcome.ref.providerId}" in model "$raw". '
          'Try `/model` to list available providers.',
        );
      }
      return outcome.ref;
    case AmbiguousBareInput():
      final options =
          outcome.candidates.map((c) => c.ref.toString()).join(', ');
      throw ConfigError(
        'model "$raw" is ambiguous — matches $options. '
        'Use `<provider>/<id>` to pick one.',
      );
    case UnknownBareInput():
      throw ConfigError(
        'could not resolve model "$raw". Use `<provider>/<id>` '
        '(e.g. `ollama/gemma4:latest`) or run `/model` to list options.',
      );
  }
}

ModelCatalog? _loadOptionalYaml(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return parseCatalogYaml(file.readAsStringSync());
  } on CatalogParseException {
    return null;
  }
}

Map<String, String> _resolveOtelHeaders(
  Map<dynamic, dynamic>? otelSection,
  Map<String, String> env,
) {
  final headers = <String, String>{};
  final envHeaders = env['OTEL_EXPORTER_OTLP_TRACES_HEADERS'] ??
      env['OTEL_EXPORTER_OTLP_HEADERS'];
  if (envHeaders != null && envHeaders.isNotEmpty) {
    headers.addAll(_parseOtelKeyValueList(envHeaders));
  }

  final yamlHeaders = otelSection?['headers'];
  if (yamlHeaders is Map) {
    for (final entry in yamlHeaders.entries) {
      headers[entry.key.toString()] = entry.value.toString();
    }
  }

  final phoenixKey = env['PHOENIX_API_KEY'];
  if (phoenixKey != null && phoenixKey.isNotEmpty) {
    headers.putIfAbsent('Authorization', () => 'Bearer $phoenixKey');
  }
  return headers;
}

Map<String, String> _resolveOtelResourceAttributes(
  Map<dynamic, dynamic>? otelSection,
  Map<String, String> env,
) {
  final attrs = <String, String>{};
  final envAttrs = env['OTEL_RESOURCE_ATTRIBUTES'];
  if (envAttrs != null && envAttrs.isNotEmpty) {
    attrs.addAll(_parseOtelKeyValueList(envAttrs));
  }

  final yamlAttrs = otelSection?['resource_attributes'];
  if (yamlAttrs is Map) {
    for (final entry in yamlAttrs.entries) {
      attrs[entry.key.toString()] = entry.value.toString();
    }
  }
  return attrs;
}

Map<String, String> _parseOtelKeyValueList(String raw) {
  final parsed = <String, String>{};
  for (final part in raw.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    final key = Uri.decodeComponent(trimmed.substring(0, idx).trim());
    final value = Uri.decodeComponent(trimmed.substring(idx + 1).trim());
    parsed[key] = value;
  }
  return parsed;
}

bool? _envBool(String? value) {
  if (value == null) return null;
  final normalized = value.toLowerCase();
  if (normalized == '1' || normalized == 'true') return true;
  if (normalized == '0' || normalized == 'false') return false;
  return null;
}

void _rejectLegacyConfig(Map<String, dynamic> fileConfig, String path) {
  final hasTopLevelProvider = fileConfig.containsKey('provider');
  final hasPerProviderKey =
      (fileConfig['anthropic'] as Map?)?.containsKey('api_key') == true ||
          (fileConfig['openai'] as Map?)?.containsKey('api_key') == true ||
          (fileConfig['mistral'] as Map?)?.containsKey('api_key') == true;
  if (!hasTopLevelProvider && !hasPerProviderKey) return;

  throw ConfigError(
    'Config file at $path uses the old (v1) format '
    '(top-level `provider:` / `<provider>.api_key:`).\n'
    'Glue now uses `active_model: <provider>/<model>` + a separate '
    '~/.glue/credentials.json.\n'
    'Migrate with: `glue credentials set <provider>` for each key, then '
    'rewrite config.yaml per docs/migration/task-22.md.',
  );
}
