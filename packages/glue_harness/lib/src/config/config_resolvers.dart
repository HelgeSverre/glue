import 'package:glue_core/glue_core.dart';
import 'package:glue_harness/src/config/config_file.dart';
import 'package:glue_harness/src/observability/observability_config.dart';
import 'package:glue_strategies/glue_strategies.dart';

// ─── Shell ──────────────────────────────────────────────────────────────────

ShellConfig resolveShellConfig(
  ShellSectionConfig? section,
  Map<String, String> env,
) {
  final exe = env['GLUE_SHELL'] ?? section?.executable;
  final modeStr = env['GLUE_SHELL_MODE'] ?? section?.mode;
  final mode = modeStr != null
      ? ShellMode.fromString(modeStr)
      : ShellMode.nonInteractive;
  return ShellConfig.detect(explicit: exe, shellEnv: env['SHELL'], mode: mode);
}

// ─── Docker ────────────────────────────────────────────────────────────────

DockerConfig resolveDockerConfig(
  DockerSectionConfig? section,
  Map<String, String> env,
) {
  final mounts = <MountEntry>[];
  final envMs = env['GLUE_DOCKER_MOUNTS'];
  if (envMs != null && envMs.isNotEmpty) {
    for (final spec in envMs.split(';')) {
      if (spec.trim().isNotEmpty) {
        mounts.add(MountEntry.parse(spec.trim()));
      }
    }
  }
  final fileMounts = section?.mounts;
  if (fileMounts != null) {
    for (final m in fileMounts) {
      mounts.add(MountEntry.parse(m));
    }
  }

  return DockerConfig(
    enabled: env['GLUE_DOCKER_ENABLED'] == '1' || (section?.enabled ?? false),
    image: env['GLUE_DOCKER_IMAGE'] ?? section?.image ?? 'ubuntu:24.04',
    shell: env['GLUE_DOCKER_SHELL'] ?? section?.shell ?? 'sh',
    fallbackToHost: section?.fallbackToHost ?? true,
    mounts: mounts,
  );
}

// ─── Web: fetch ────────────────────────────────────────────────────────────

WebFetchConfig resolveFetchConfig(
  FetchSectionConfig? section,
  Map<String, String> env,
) {
  return WebFetchConfig(
    jinaApiKey: env['JINA_API_KEY'] ?? section?.jinaApiKey,
    allowJinaFallback: section?.allowJinaFallback ?? true,
    timeoutSeconds:
        section?.timeoutSeconds ?? AppConstants.webFetchTimeoutSeconds,
    maxBytes: section?.maxBytes ?? AppConstants.webFetchMaxBytes,
    defaultMaxTokens:
        section?.maxTokens ?? AppConstants.webFetchDefaultMaxTokens,
  );
}

// ─── Web: search ───────────────────────────────────────────────────────────

WebSearchConfig resolveSearchConfig(
  SearchSectionConfig? section,
  Map<String, String> env,
) {
  final providerStr = env['GLUE_SEARCH_PROVIDER'] ?? section?.provider;
  final provider = providerStr != null
      ? enumFromName(
          WebSearchProviderType.values,
          providerStr,
          fallback: WebSearchProviderType.brave,
        )
      : null;

  return WebSearchConfig(
    provider: provider,
    braveApiKey: env['BRAVE_API_KEY'] ?? section?.braveApiKey,
    tavilyApiKey: env['TAVILY_API_KEY'] ?? section?.tavilyApiKey,
    firecrawlApiKey: env['FIRECRAWL_API_KEY'] ?? section?.firecrawlApiKey,
    firecrawlBaseUrl: section?.firecrawlBaseUrl,
    timeoutSeconds:
        section?.timeoutSeconds ?? AppConstants.webSearchTimeoutSeconds,
    defaultMaxResults:
        section?.maxResults ?? AppConstants.webSearchDefaultMaxResults,
  );
}

// ─── Web: pdf ──────────────────────────────────────────────────────────────

PdfConfig resolvePdfConfig(
  PdfSectionConfig? section,
  Map<String, String> env,
  ModelCatalog catalog,
  CredentialStore credentials,
) {
  final ocrProvider = enumFromName(
    OcrProviderType.values,
    env['GLUE_OCR_PROVIDER'] ?? section?.ocrProvider,
    fallback: OcrProviderType.mistral,
  );

  final mistralProvider = catalog.providers['mistral'];
  final openaiProvider = catalog.providers['openai'];
  final pdfMistralApiKey =
      section?.mistralApiKey ??
      (mistralProvider != null
          ? credentials.resolveForProvider(mistralProvider)
          : null);
  final pdfOpenaiApiKey =
      section?.openaiApiKey ??
      (openaiProvider != null
          ? credentials.resolveForProvider(openaiProvider)
          : null);

  return PdfConfig(
    maxBytes: section?.maxBytes ?? AppConstants.pdfMaxBytes,
    timeoutSeconds: section?.timeoutSeconds ?? AppConstants.pdfTimeoutSeconds,
    enableOcrFallback: section?.enableOcrFallback ?? true,
    ocrProvider: ocrProvider,
    mistralApiKey: pdfMistralApiKey,
    openaiApiKey: pdfOpenaiApiKey,
  );
}

// ─── Web: browser ──────────────────────────────────────────────────────────

BrowserConfig resolveBrowserConfig(
  BrowserSectionConfig? section,
  Map<String, String> env,
) {
  final backend = enumFromName(
    BrowserBackend.values,
    env['GLUE_BROWSER_BACKEND'] ?? section?.backend,
    fallback: BrowserBackend.local,
  );

  return BrowserConfig(
    backend: backend,
    headed: section?.headed ?? false,
    dockerImage: section?.docker?.image ?? AppConstants.browserDockerImage,
    dockerPort: section?.docker?.port ?? AppConstants.browserDockerPort,
    steelApiKey: env['STEEL_API_KEY'] ?? section?.steel?.apiKey,
    browserbaseApiKey:
        env['BROWSERBASE_API_KEY'] ?? section?.browserbase?.apiKey,
    browserbaseProjectId:
        env['BROWSERBASE_PROJECT_ID'] ?? section?.browserbase?.projectId,
    browserlessBaseUrl: section?.browserless?.baseUrl,
    browserlessApiKey:
        env['BROWSERLESS_API_KEY'] ?? section?.browserless?.apiKey,
    anchorApiKey: env['ANCHOR_API_KEY'] ?? section?.anchor?.apiKey,
    hyperbrowserApiKey:
        env['HYPERBROWSER_API_KEY'] ?? section?.hyperbrowser?.apiKey,
  );
}

// ─── Web: aggregate ────────────────────────────────────────────────────────

WebConfig resolveWebConfig(
  WebSectionConfig? section,
  Map<String, String> env,
  ModelCatalog catalog,
  CredentialStore credentials,
) {
  return WebConfig(
    fetch: resolveFetchConfig(section?.fetch, env),
    search: resolveSearchConfig(section?.search, env),
    pdf: resolvePdfConfig(section?.pdf, env, catalog, credentials),
    browser: resolveBrowserConfig(section?.browser, env),
  );
}

// ─── Observability ─────────────────────────────────────────────────────────

ObservabilityConfig resolveObservabilityConfig(
  ObservabilitySectionConfig? section,
  Map<String, String> env,
) {
  final debug = env['GLUE_DEBUG'] == '1' || (section?.debug ?? false);

  final otelSection = section?.otel;
  final otelEndpoint =
      otelSection?.endpoint ??
      env['OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'] ??
      env['OTEL_EXPORTER_OTLP_ENDPOINT'] ??
      env['PHOENIX_COLLECTOR_ENDPOINT'];

  final otelHeaders = <String, String>{
    ...?_parseOtelEnvHeaders(env),
    ...?otelSection?.headers,
  };
  final phoenixKey = env['PHOENIX_API_KEY'];
  if (phoenixKey != null && phoenixKey.isNotEmpty) {
    otelHeaders.putIfAbsent('Authorization', () => 'Bearer $phoenixKey');
  }

  final otelResourceAttributes = <String, String>{
    ...?_parseOtelEnvAttrs(env),
    ...?otelSection?.resourceAttributes,
  };
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

  final otelEnabled =
      otelSection?.enabled ??
      (envBool(env['OTEL_SDK_DISABLED']) != true &&
          otelEndpoint != null &&
          otelEndpoint.isNotEmpty);

  final otel = OtelConfig(
    enabled: otelEnabled,
    endpoint: otelEndpoint,
    headers: otelHeaders,
    serviceName: otelSection?.serviceName ?? env['OTEL_SERVICE_NAME'] ?? 'glue',
    resourceAttributes: otelResourceAttributes,
    timeoutMilliseconds: otelSection?.timeoutMilliseconds ?? 10000,
  );

  return ObservabilityConfig(
    debug: debug,
    maxBodyBytes: section?.maxBodyBytes ?? 65536,
    redact: section?.redact ?? true,
    otel: otel,
  );
}

// ─── Skills ────────────────────────────────────────────────────────────────

List<String> resolveSkillPaths(
  SkillsSectionConfig? section,
  Map<String, String> env,
  bool isWindows,
) {
  final paths = <String>[];
  final envPaths = env['GLUE_SKILLS_PATHS'];
  if (envPaths != null && envPaths.isNotEmpty) {
    final sep = isWindows ? ';' : ':';
    paths.addAll(envPaths.split(sep).where((s) => s.isNotEmpty));
  }
  if (section?.paths != null) {
    paths.addAll(section!.paths!);
  }
  return paths;
}

// ─── Helpers ───────────────────────────────────────────────────────────────

/// Resolves an enum member by its `.name` (or an optional [alias] selector,
/// e.g. a human label) against a raw config/env [value]. Returns [fallback]
/// when [value] is null or matches no member.
T enumFromName<T extends Enum>(
  Iterable<T> values,
  String? value, {
  required T fallback,
  String Function(T value)? alias,
}) {
  if (value == null) return fallback;
  return values.firstWhere(
    (v) => v.name == value || (alias != null && alias(v) == value),
    orElse: () => fallback,
  );
}

Map<String, String>? _parseOtelEnvHeaders(Map<String, String> env) {
  final raw =
      env['OTEL_EXPORTER_OTLP_TRACES_HEADERS'] ??
      env['OTEL_EXPORTER_OTLP_HEADERS'];
  if (raw == null || raw.isEmpty) return null;
  return _parseOtelKeyValueList(raw);
}

Map<String, String>? _parseOtelEnvAttrs(Map<String, String> env) {
  final raw = env['OTEL_RESOURCE_ATTRIBUTES'];
  if (raw == null || raw.isEmpty) return null;
  return _parseOtelKeyValueList(raw);
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

/// Parses an env-var string as a tri-state bool: `true`/`1` → true,
/// `false`/`0` → false, anything else (including null) → null so callers
/// can fall through to a YAML key or default.
bool? envBool(String? value) {
  if (value == null) return null;
  final normalized = value.toLowerCase();
  if (normalized == '1' || normalized == 'true') return true;
  if (normalized == '0' || normalized == 'false') return false;
  return null;
}
