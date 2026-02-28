import 'package:glue/src/config/glue_config.dart';

/// What a model is good at.
enum ModelCapability { coding, reasoning, research, fast, cheap, vision }

/// Relative cost bracket.
enum CostTier { free, low, medium, high, premium }

/// Relative speed bracket.
enum SpeedTier { instant, fast, standard, slow }

/// A curated model entry in the registry.
class ModelEntry {
  final String displayName;
  final String modelId;
  final LlmProvider provider;
  final Set<ModelCapability> capabilities;
  final CostTier cost;
  final SpeedTier speed;
  final String tagline;
  final bool isDefault;

  const ModelEntry({
    required this.displayName,
    required this.modelId,
    required this.provider,
    required this.capabilities,
    required this.cost,
    required this.speed,
    required this.tagline,
    this.isDefault = false,
  });

  /// Dollar-sign indicator: $ to $$$$.
  String get costLabel => switch (cost) {
        CostTier.free => 'free',
        CostTier.low => r'$',
        CostTier.medium => r'$$',
        CostTier.high => r'$$$',
        CostTier.premium => r'$$$$',
      };

  /// Speed dots: more filled = faster.
  String get speedLabel => switch (speed) {
        SpeedTier.instant => '\u25cf\u25cf\u25cf',
        SpeedTier.fast => '\u25cf\u25cf\u25cb',
        SpeedTier.standard => '\u25cf\u25cb\u25cb',
        SpeedTier.slow => '\u25cb\u25cb\u25cb',
      };

  @override
  String toString() => 'ModelEntry($displayName, $modelId)';
}

/// Curated catalog of supported models.
class ModelRegistry {
  ModelRegistry._();

  static const List<ModelEntry> models = [
    // ── Anthropic ──────────────────────────────────────────────
    ModelEntry(
      displayName: 'Claude Opus 4.6',
      modelId: 'claude-opus-4-6',
      provider: LlmProvider.anthropic,
      capabilities: {ModelCapability.coding, ModelCapability.reasoning},
      cost: CostTier.premium,
      speed: SpeedTier.slow,
      tagline: 'Most capable',
    ),
    ModelEntry(
      displayName: 'Claude Sonnet 4.6',
      modelId: 'claude-sonnet-4-6',
      provider: LlmProvider.anthropic,
      capabilities: {ModelCapability.coding, ModelCapability.reasoning},
      cost: CostTier.high,
      speed: SpeedTier.standard,
      tagline: 'Balanced power and speed',
      isDefault: true,
    ),
    ModelEntry(
      displayName: 'Claude Haiku 3.5',
      modelId: 'claude-haiku-3-5',
      provider: LlmProvider.anthropic,
      capabilities: {ModelCapability.fast, ModelCapability.cheap},
      cost: CostTier.low,
      speed: SpeedTier.fast,
      tagline: 'Fast and cheap',
    ),

    // ── OpenAI ─────────────────────────────────────────────────
    ModelEntry(
      displayName: 'GPT-4.1',
      modelId: 'gpt-4.1',
      provider: LlmProvider.openai,
      capabilities: {ModelCapability.coding, ModelCapability.reasoning},
      cost: CostTier.high,
      speed: SpeedTier.standard,
      tagline: 'Latest flagship',
      isDefault: true,
    ),
    ModelEntry(
      displayName: 'GPT-4.1 Mini',
      modelId: 'gpt-4.1-mini',
      provider: LlmProvider.openai,
      capabilities: {
        ModelCapability.fast,
        ModelCapability.cheap,
        ModelCapability.coding,
      },
      cost: CostTier.low,
      speed: SpeedTier.fast,
      tagline: 'Fast and affordable',
    ),
    ModelEntry(
      displayName: 'o3',
      modelId: 'o3',
      provider: LlmProvider.openai,
      capabilities: {ModelCapability.reasoning},
      cost: CostTier.premium,
      speed: SpeedTier.slow,
      tagline: 'Deep reasoning',
    ),

    // ── Mistral ─────────────────────────────────────────────────
    ModelEntry(
      displayName: 'Mistral Large',
      modelId: 'mistral-large-latest',
      provider: LlmProvider.mistral,
      capabilities: {ModelCapability.coding, ModelCapability.reasoning},
      cost: CostTier.high,
      speed: SpeedTier.standard,
      tagline: 'Flagship multimodal',
      isDefault: true,
    ),
    ModelEntry(
      displayName: 'Mistral Small',
      modelId: 'mistral-small-latest',
      provider: LlmProvider.mistral,
      capabilities: {ModelCapability.fast, ModelCapability.coding},
      cost: CostTier.low,
      speed: SpeedTier.fast,
      tagline: 'Fast and efficient',
    ),
    ModelEntry(
      displayName: 'Codestral',
      modelId: 'codestral-latest',
      provider: LlmProvider.mistral,
      capabilities: {ModelCapability.coding, ModelCapability.fast},
      cost: CostTier.medium,
      speed: SpeedTier.fast,
      tagline: 'Code specialist',
    ),

    // ── Ollama ─────────────────────────────────────────────────
    ModelEntry(
      displayName: 'Llama 3.2',
      modelId: 'llama3.2',
      provider: LlmProvider.ollama,
      capabilities: {ModelCapability.coding, ModelCapability.fast},
      cost: CostTier.free,
      speed: SpeedTier.fast,
      tagline: 'Local and free',
      isDefault: true,
    ),
  ];

  /// Finds a model by its exact ID, or returns null.
  static ModelEntry? findById(String modelId) {
    for (final m in models) {
      if (m.modelId == modelId) return m;
    }
    return null;
  }

  /// Finds a model by fuzzy match on [ModelEntry.modelId] or [ModelEntry.displayName].
  static ModelEntry? findByName(String query) {
    final q = query.toLowerCase();
    // Exact modelId match first.
    for (final m in models) {
      if (m.modelId.toLowerCase() == q) return m;
    }
    // Exact displayName match.
    for (final m in models) {
      if (m.displayName.toLowerCase() == q) return m;
    }
    // Substring match on either.
    for (final m in models) {
      if (m.modelId.toLowerCase().contains(q) ||
          m.displayName.toLowerCase().contains(q)) {
        return m;
      }
    }
    return null;
  }

  /// All models for a given provider.
  static List<ModelEntry> forProvider(LlmProvider provider) =>
      models.where((m) => m.provider == provider).toList();

  /// Models whose provider has a configured API key (or is Ollama).
  static List<ModelEntry> available(GlueConfig config) {
    return models.where((m) {
      return switch (m.provider) {
        LlmProvider.anthropic =>
          config.anthropicApiKey != null && config.anthropicApiKey!.isNotEmpty,
        LlmProvider.openai =>
          config.openaiApiKey != null && config.openaiApiKey!.isNotEmpty,
        LlmProvider.mistral =>
          config.mistralApiKey != null && config.mistralApiKey!.isNotEmpty,
        LlmProvider.ollama => true,
      };
    }).toList();
  }

  /// Models with a given capability.
  static List<ModelEntry> withCapability(ModelCapability cap) =>
      models.where((m) => m.capabilities.contains(cap)).toList();

  /// The default model for a provider.
  static ModelEntry defaultFor(LlmProvider provider) =>
      models.firstWhere((m) => m.provider == provider && m.isDefault);

  /// The default model ID string for a provider.
  static String defaultModelId(LlmProvider provider) =>
      defaultFor(provider).modelId;
}
