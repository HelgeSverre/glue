import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/context/context_config.dart';

/// Default context window to assume when the model has no catalog entry.
const int defaultContextWindow = 32768;

/// Tokens reserved for output + tool-schema overhead when no explicit value
/// is available.
const int _defaultOutputReserve = 9216; // 8192 output + 1024 tool schemas

/// Computes the usable token budget for a given model.
///
/// Thresholds are expressed as fractions of [inputBudget] (context window
/// minus headroom reserved for output).
///
/// {@category Context}
class ContextBudget {
  /// Total context window, in tokens.
  final int contextWindowTokens;

  /// Maximum output tokens the model can produce.
  final int maxOutputTokens;

  /// Fraction at which Tier 2 (summarization) fires.
  final double compactThreshold;

  /// Fraction at which Tier 3 (sliding-window trim) fires.
  final double criticalThreshold;

  /// Tokens reserved for output + tool schemas.
  final int reservedHeadroom;

  const ContextBudget({
    required this.contextWindowTokens,
    required this.maxOutputTokens,
    this.compactThreshold = 0.80,
    this.criticalThreshold = 0.95,
    this.reservedHeadroom = _defaultOutputReserve,
  });

  /// Constructs a [ContextBudget] from a catalog [ModelDef] and optional
  /// [ContextConfig].
  factory ContextBudget.fromModelDef(ModelDef def, {ContextConfig? config}) {
    final contextWindow = def.contextWindow ?? defaultContextWindow;
    final maxOutput = def.maxOutputTokens ?? 8192;
    // Reserve output space + ~1024 tokens for tool schema definitions.
    final headroom = maxOutput + 1024;

    return ContextBudget(
      contextWindowTokens: contextWindow,
      maxOutputTokens: maxOutput,
      compactThreshold: config?.compactThreshold ?? 0.80,
      criticalThreshold: config?.criticalThreshold ?? 0.95,
      reservedHeadroom: headroom,
    );
  }

  /// Usable input budget = context window − reserved headroom.
  int get inputBudget => contextWindowTokens - reservedHeadroom;

  /// Token count at which Tier 2 (auto-compact) should fire.
  int get compactAt => (inputBudget * compactThreshold).round();

  /// Token count at which Tier 3 (hard sliding-window trim) should fire.
  int get criticalAt => (inputBudget * criticalThreshold).round();
}
