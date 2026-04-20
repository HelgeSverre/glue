/// Turns a user-typed model identifier into a concrete [ModelRef].
///
/// Two policies matter here:
///
/// 1. **Explicit `provider/id` is sacred.** When the input parses as a
///    [ModelRef], we never fuzzy-match. If the pair exists in the catalog we
///    return [ResolvedExact]; otherwise we pass it through verbatim as
///    [ResolvedPassthrough]. This lets users target freshly-pulled Ollama
///    tags or off-catalog API ids without the catalog rewriting their input.
///
/// 2. **Bare ids must match exactly.** Case-insensitive equality against
///    `model.id` or `model.name`, across every provider. Zero hits →
///    [UnknownBareInput]. Exactly one → [ResolvedExact]. Multiple →
///    [AmbiguousBareInput] with the candidate list; the caller decides
///    whether to surface a disambiguation prompt or error.
///
/// Substring fallback is intentionally absent — the previous behaviour
/// silently rewrote `gemma4` into `gemma4:26b`, which masked real input
/// errors.
library;

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';

/// The outcome of [resolveModelInput].
sealed class ModelResolution {
  const ModelResolution();
}

/// The input maps to a specific entry in the catalog.
class ResolvedExact extends ModelResolution {
  const ResolvedExact({required this.ref, required this.def});

  final ModelRef ref;
  final ModelDef def;
}

/// The input was an explicit `provider/id` for a provider Glue knows about
/// but a model that isn't in the curated catalog. Send it to the provider
/// as-is; the user knows what they're asking for.
class ResolvedPassthrough extends ModelResolution {
  const ResolvedPassthrough({required this.ref, this.providerKnown = true});

  final ModelRef ref;

  /// True when `providerId` resolves to a registered provider. False means
  /// the user typed `foo/bar` and `foo` is nowhere in the catalog — the
  /// caller should surface this as an error rather than trying to use it.
  final bool providerKnown;
}

/// A bare input matched multiple catalog entries. The caller should ask the
/// user to disambiguate with `<provider>/<id>`.
class AmbiguousBareInput extends ModelResolution {
  const AmbiguousBareInput({required this.raw, required this.candidates});

  final String raw;
  final List<ModelCandidate> candidates;
}

/// A bare input with no slash matched nothing in the catalog.
class UnknownBareInput extends ModelResolution {
  const UnknownBareInput({required this.raw});

  final String raw;
}

class ModelCandidate {
  const ModelCandidate({required this.ref, required this.def});

  final ModelRef ref;
  final ModelDef def;
}

/// Resolve [raw] against [catalog]. See library doc for the rules.
ModelResolution resolveModelInput(String raw, ModelCatalog catalog) {
  final parsed = ModelRef.tryParse(raw);
  if (parsed != null) {
    final provider = catalog.providers[parsed.providerId];
    if (provider == null) {
      return ResolvedPassthrough(ref: parsed, providerKnown: false);
    }
    final def = provider.models[parsed.modelId];
    if (def != null) {
      return ResolvedExact(ref: parsed, def: def);
    }
    return ResolvedPassthrough(ref: parsed);
  }

  final needle = raw.toLowerCase();
  final hits = <ModelCandidate>[];
  for (final provider in catalog.providers.values) {
    for (final model in provider.models.values) {
      if (model.id.toLowerCase() == needle ||
          model.name.toLowerCase() == needle) {
        hits.add(
          ModelCandidate(
            ref: ModelRef(providerId: provider.id, modelId: model.id),
            def: model,
          ),
        );
      }
    }
  }

  if (hits.isEmpty) return UnknownBareInput(raw: raw);
  if (hits.length == 1) {
    return ResolvedExact(ref: hits.single.ref, def: hits.single.def);
  }
  return AmbiguousBareInput(raw: raw, candidates: hits);
}
