/// Runtime types for the Glue model/provider catalog.
///
/// The catalog is the source of truth for which providers and models Glue
/// knows about. At startup, a bundled catalog (generated from
/// `docs/reference/models.yaml` into `models_generated.dart`) is merged with
/// optional cached remote and local override YAML files.
library;

/// The canonical capability names used by the catalog.
///
/// Individual model entries list a subset in their `capabilities` field.
/// The model picker filters on these via `selection.default_filter.capabilities`.
class Capability {
  static const chat = 'chat';
  static const streaming = 'streaming';
  static const tools = 'tools';
  static const parallelTools = 'parallel_tools';
  static const vision = 'vision';
  static const files = 'files';
  static const json = 'json';
  static const reasoning = 'reasoning';
  static const coding = 'coding';
  static const local = 'local';
  static const browser = 'browser';
  static const binaryToolResults = 'binary_tool_results';

  static const all = <String>{
    chat,
    streaming,
    tools,
    parallelTools,
    vision,
    files,
    json,
    reasoning,
    coding,
    local,
    browser,
    binaryToolResults,
  };
}

/// Top-level catalog object.
class ModelCatalog {
  const ModelCatalog({
    required this.version,
    required this.updatedAt,
    required this.defaults,
    required this.capabilities,
    required this.providers,
  });

  final int version;
  final String updatedAt;
  final DefaultsConfig defaults;

  /// Capability id → human description.
  final Map<String, String> capabilities;

  /// Provider id → provider definition.
  final Map<String, ProviderDef> providers;
}

class DefaultsConfig {
  const DefaultsConfig({
    required this.model,
    this.smallModel,
    this.localModel,
  });

  final String model;
  final String? smallModel;
  final String? localModel;
}

/// How a provider obtains its credential.
///
/// - [apiKey] — a single string the user pastes in (or reads from an env var).
/// - [oauth] — an interactive OAuth flow (device code, PKCE). The adapter
///   drives the flow via [ProviderAdapter.beginInteractiveAuth] and decides
///   what fields to store.
/// - [none] — no credential needed (Ollama, local-vllm).
enum AuthKind { apiKey, oauth, none }

class AuthSpec {
  const AuthSpec({required this.kind, this.envVar, this.helpUrl});

  final AuthKind kind;

  /// Name of the environment variable that backs this provider's API key
  /// when [kind] is [AuthKind.apiKey]. When set, env wins over stored.
  final String? envVar;

  /// "Where do I get a key?" link shown in the `/provider add` form.
  final String? helpUrl;
}

class ProviderDef {
  const ProviderDef({
    required this.id,
    required this.name,
    required this.adapter,
    required this.auth,
    required this.models,
    this.compatibility,
    this.enabled = true,
    this.baseUrl,
    this.docsUrl,
    this.requestHeaders = const {},
  });

  final String id;
  final String name;

  /// Wire protocol: `anthropic` | `openai` | `gemini` | `mistral`.
  final String adapter;

  /// Quirks profile: `openai` | `groq` | `ollama` | `openrouter` | `vllm` | `mistral`.
  /// When omitted, callers should treat this as equal to [adapter].
  final String? compatibility;

  final bool enabled;
  final String? baseUrl;
  final String? docsUrl;
  final AuthSpec auth;
  final Map<String, String> requestHeaders;

  /// Model id → model definition.
  final Map<String, ModelDef> models;
}

class ModelDef {
  const ModelDef({
    required this.id,
    required this.name,
    String? apiId,
    this.recommended = false,
    this.isDefault = false,
    this.enabled = true,
    this.capabilities = const {},
    this.contextWindow,
    this.maxOutputTokens,
    this.speed,
    this.cost,
    this.notes,
  }) : apiId = apiId ?? id;

  /// Catalog key — stable, user-facing (CLI, config, session files, URLs).
  final String id;

  /// Human display label.
  final String name;

  /// The exact string sent to the provider's API. Defaults to [id] when the
  /// catalog entry doesn't override it. Let upstream slugs like
  /// `openai/gpt-oss-120b` live here instead of leaking into user-facing ids.
  final String apiId;

  final bool recommended;
  final bool isDefault;

  /// When `false`, the model picker hides this entry but the catalog still
  /// records it. Useful for surfaces that aren't yet wired up at runtime
  /// (e.g. agents that need a background-execution runner).
  final bool enabled;

  final Set<String> capabilities;
  final int? contextWindow;
  final int? maxOutputTokens;
  final String? speed;
  final String? cost;
  final String? notes;
}
