import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:glue_harness/src/catalog/catalog_loader.dart';
import 'package:glue_harness/src/catalog/catalog_parser.dart';
import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/catalog/model_resolver.dart';
import 'package:glue_harness/src/catalog/models_generated.dart';
import 'package:glue_harness/src/config/approval_mode.dart';
import 'package:glue_harness/src/config/config_file.dart';
import 'package:glue_harness/src/config/config_resolvers.dart';
import 'package:glue_harness/src/config/mcp_config.dart';
import 'package:glue_harness/src/core/environment.dart';
import 'package:glue_strategies/glue_strategies.dart';
import 'package:glue_harness/src/observability/observability_config.dart';

/// Splits a path-list env var using platform-appropriate separators.
/// Unix uses `:` (like `$PATH`), Windows uses `;`.
List<String> splitPathList(String value, {bool? isWindows}) {
  final sep = (isWindows ?? Platform.isWindows) ? ';' : ':';
  return value.split(sep).where((s) => s.isNotEmpty).toList();
}

/// Configuration for how Glue sources the bundled/remote model catalog.
class CatalogSourceConfig {
  const CatalogSourceConfig({this.refresh = 'manual', this.remoteUrl});

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
    this.skillPaths = const [],
    this.approvalMode = ApprovalMode.confirm,
    this.titleGenerationEnabled = true,
    this.anthropicPromptCache = true,
    this.mcp = const McpConfig(),
    this.runtime,
    Map<String, Object?>? runtimeOptions,
  }) : shellConfig = shellConfig ?? const ShellConfig(),
       dockerConfig = dockerConfig ?? const DockerConfig(),
       webConfig = webConfig ?? const WebConfig(),
       runtimeOptions = runtimeOptions ?? const {};

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
  /// Not final — ServiceLocator swaps this after observability is constructed
  /// so adapters can thread a logging HTTP factory into their LLM clients.
  AdapterRegistry adapters;

  final int maxSubagentDepth;
  final int bashMaxLines;
  final ShellConfig shellConfig;
  final DockerConfig dockerConfig;
  final WebConfig webConfig;
  final ObservabilityConfig observability;
  final List<String> skillPaths;
  final ApprovalMode approvalMode;

  /// When `false`, session title generation is skipped entirely. No LLM
  /// client is created and the session title remains `null`.
  ///
  /// Resolution order: `GLUE_TITLE_GENERATION_ENABLED` env var →
  /// `title_generation_enabled` YAML key → default `true`.
  final bool titleGenerationEnabled;

  /// When `true` (default), Anthropic requests include a top-level
  /// `cache_control: {type: "ephemeral"}` directive that enables
  /// auto-caching of the largest stable prefix of the request. Disable
  /// for proxies that reject the field, or for measurement comparisons.
  ///
  /// Resolution order: `GLUE_ANTHROPIC_PROMPT_CACHE` env var →
  /// `anthropic_prompt_cache` YAML key → default `true`.
  ///
  /// Caching is GA on Claude 4.x and silently no-op on older Anthropic
  /// models. The flag has no effect on non-Anthropic providers.
  final bool anthropicPromptCache;

  /// MCP (Model Context Protocol) configuration — list of configured
  /// servers, tool policy, reconnect defaults. Empty by default.
  final McpConfig mcp;

  /// Selected runtime adapter: `'host'`, `'docker'`, or the name of a
  /// registered cloud adapter (e.g. `'daytona'`). When null, resolution
  /// falls back to legacy behaviour — Docker if `dockerConfig.enabled`,
  /// host otherwise — so existing configs keep working unchanged.
  ///
  /// Resolution order: `GLUE_RUNTIME` env var → `runtime:` YAML key →
  /// legacy fallback above.
  final String? runtime;

  /// Per-runtime options keyed by runtime id. For example, when
  /// `runtime: daytona` is selected the `daytona` key holds
  /// `{api_key, base_url, image}` — adapters parse this on startup.
  ///
  /// Stored as untyped JSON-ish data here to keep `glue_harness` free
  /// of dependencies on cloud-adapter packages.
  final Map<String, Object?> runtimeOptions;

  /// Resolves the effective runtime name from [runtime] and the legacy
  /// `docker.enabled` flag.
  String get effectiveRuntime {
    if (runtime != null && runtime!.isNotEmpty) return runtime!;
    return dockerConfig.enabled ? 'docker' : 'host';
  }

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
    final def =
        provider.models[ref.modelId] ??
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
  }) {
    return GlueConfig(
      activeModel: activeModel ?? this.activeModel,
      smallModel: smallModel,
      profiles: profiles,
      catalog: catalog,
      catalogData: catalogData,
      credentials: credentials,
      adapters: adapters,
      maxSubagentDepth: maxSubagentDepth,
      bashMaxLines: bashMaxLines,
      shellConfig: shellConfig,
      dockerConfig: dockerConfig,
      webConfig: webConfig,
      observability: observability ?? this.observability,
      skillPaths: skillPaths,
      approvalMode: approvalMode,
      titleGenerationEnabled: titleGenerationEnabled,
      anthropicPromptCache: anthropicPromptCache,
      mcp: mcp,
      runtime: runtime,
      runtimeOptions: runtimeOptions,
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
    final env = environment?.vars ?? Platform.environment;
    final home = env['HOME'] ?? '.';

    final configYamlPath =
        configPath ?? environment?.configYamlPath ?? '$home/.glue/config.yaml';
    final configFile = File(configYamlPath);
    final rawYaml = configFile.existsSync()
        ? () {
            final content = configFile.readAsStringSync();
            final yaml = loadYaml(content);
            if (yaml is YamlMap) return _yamlMapToJsonMap(yaml);
            return <String, dynamic>{};
          }()
        : <String, dynamic>{};

    // Reject legacy v1 shape with a migration message.
    if (rawYaml.isNotEmpty) _rejectLegacyConfig(rawYaml, configYamlPath);

    // Deserialize raw YAML into typed ConfigFile (nullable, snake_case).
    final cfg = rawYaml.isNotEmpty
        ? ConfigFileMapper.fromMap(rawYaml)
        : const ConfigFile();

    // Catalog: bundled → optional cached remote → optional local overrides.
    final catalog =
        catalogOverride ??
        loadCatalog(
          bundled: bundledCatalog,
          cachedRemote: _loadOptionalYaml(
            environment?.catalogCachePath ??
                env['GLUE_CATALOG_CACHE'] ??
                p.join(home, '.glue/cache/models.yaml'),
          ),
          localOverrides: _loadOptionalYaml(
            environment?.modelsYamlPath ?? p.join(home, '.glue/models.yaml'),
          ),
        );

    final credentials =
        credentialsOverride ??
        CredentialStore(
          path:
              '${environment?.glueDir ?? p.join(home, '.glue')}/credentials.json',
          env: Map<String, String>.from(env),
        );

    final adapters =
        adaptersOverride ??
        AdapterRegistry([
          AnthropicAdapter(),
          OpenAiCompatibleAdapter(),
          OllamaAdapter(),
          CopilotAdapter(credentialStore: credentials),
          GeminiProvider(),
        ]);

    // Resolve active model: CLI flag → GLUE_MODEL → config file → catalog default.
    final rawActive =
        cliModel ??
        env['GLUE_MODEL'] ??
        cfg.activeModel ??
        catalog.defaults.model;
    final activeModel = _resolveModelRef(rawActive, catalog);

    final rawSmall = cfg.smallModel ?? catalog.defaults.smallModel;
    final smallModel = rawSmall != null
        ? _resolveModelRef(rawSmall, catalog)
        : null;

    // Catalog source section.
    final catalogConfig = CatalogSourceConfig(
      refresh: cfg.catalog?.refresh ?? 'manual',
      remoteUrl: cfg.catalog?.remoteUrl != null
          ? Uri.tryParse(cfg.catalog!.remoteUrl!)
          : null,
    );

    // Profiles: Map<String, ModelRef>.
    final profiles = <String, ModelRef>{};
    final profilesYaml = cfg.profiles;
    if (profilesYaml != null) {
      for (final entry in profilesYaml.entries) {
        profiles[entry.key] = _resolveModelRef(entry.value, catalog);
      }
    }

    // ─── Resolve typed configs from ConfigFile + env overrides ───────────

    final bashMaxLines = cfg.bash?.maxLines ?? AppConstants.bashMaxLinesDefault;

    final shellConfig = resolveShellConfig(cfg.shell, env);
    final dockerConfig = resolveDockerConfig(cfg.docker, env);
    final webConfig = resolveWebConfig(cfg.web, env, catalog, credentials);
    final observabilityConfig = resolveObservabilityConfig(
      cfg.observability,
      env,
    );
    final skillPaths = resolveSkillPaths(
      cfg.skills,
      env,
      environment?.isWindows ?? false,
    );

    // Approval mode.
    final approvalMode = enumFromName(
      ApprovalMode.values,
      env['GLUE_APPROVAL_MODE'] ?? cfg.approvalMode,
      fallback: ApprovalMode.confirm,
      alias: (m) => m.label,
    );

    // Title generation toggle. Env wins over YAML; default enabled. A
    // present-but-unparseable env value reads as `false` (legacy behaviour).
    final titleEnabledEnv = env['GLUE_TITLE_GENERATION_ENABLED'];
    final titleGenerationEnabled = titleEnabledEnv != null
        ? (envBool(titleEnabledEnv) ?? false)
        : (cfg.titleGenerationEnabled ?? true);

    // Anthropic prompt caching. Env wins over YAML; default enabled. A
    // present-but-unparseable env value reads as `false` (legacy behaviour).
    final cacheEnabledEnv = env['GLUE_ANTHROPIC_PROMPT_CACHE'];
    final anthropicPromptCache = cacheEnabledEnv != null
        ? (envBool(cacheEnabledEnv) ?? false)
        : (cfg.anthropicPromptCache ?? true);

    // MCP servers (still hand-parsed — needs env-var expansion + validation).
    final mcp = parseMcpConfig(rawYaml.isNotEmpty ? rawYaml['mcp'] : null, env);

    // Runtime adapter selector.
    final runtimeName = env['GLUE_RUNTIME'] ?? cfg.runtime;
    final runtimeOptions = <String, Object?>{};
    if (runtimeName != null && runtimeName.isNotEmpty) {
      final section = rawYaml[runtimeName] as Map?;
      if (section != null) {
        for (final entry in section.entries) {
          runtimeOptions[entry.key.toString()] = entry.value;
        }
      }
    }

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
      skillPaths: skillPaths,
      approvalMode: approvalMode,
      titleGenerationEnabled: titleGenerationEnabled,
      anthropicPromptCache: anthropicPromptCache,
      mcp: mcp,
      runtime: runtimeName,
      runtimeOptions: runtimeOptions,
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
          'Try `/models` to list available providers.',
        );
      }
      return outcome.ref;
    case AmbiguousBareInput():
      final options = outcome.candidates
          .map((c) => c.ref.toString())
          .join(', ');
      throw ConfigError(
        'model "$raw" is ambiguous — matches $options. '
        'Use `<provider>/<id>` to pick one.',
      );
    case UnknownBareInput():
      throw ConfigError(
        'could not resolve model "$raw". Use `<provider>/<id>` '
        '(e.g. `ollama/gemma4:latest`) or run `/models` to list options.',
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

Map<String, dynamic> _yamlMapToJsonMap(YamlMap yaml) =>
    Map<String, dynamic>.fromEntries(
      yaml.entries.map(
        (e) => MapEntry(e.key as String, _normalizeYamlValue(e.value)),
      ),
    );

Object? _normalizeYamlValue(Object? value) {
  if (value is YamlMap) return _yamlMapToJsonMap(value);
  if (value is YamlList) return value.map(_normalizeYamlValue).toList();
  return value;
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
