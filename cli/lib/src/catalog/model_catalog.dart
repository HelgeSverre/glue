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
enum AuthKind { env, none, prompt }

class AuthSpec {
  const AuthSpec({required this.kind, this.envVar});

  final AuthKind kind;

  /// Present when [kind] is [AuthKind.env].
  final String? envVar;
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
    this.recommended = false,
    this.isDefault = false,
    this.capabilities = const {},
    this.contextWindow,
    this.maxOutputTokens,
    this.speed,
    this.cost,
    this.notes,
  });

  final String id;
  final String name;
  final bool recommended;
  final bool isDefault;
  final Set<String> capabilities;
  final int? contextWindow;
  final int? maxOutputTokens;
  final String? speed;
  final String? cost;
  final String? notes;
}
