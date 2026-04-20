/// Formatting helpers for how the active model is surfaced to the user.
///
/// Two audiences:
/// - **Status bar** (every render, must be compact): shows
///   `<provider> · <apiId>` — the wire address the provider actually sees.
/// - **`/info` command** (occasional, can be verbose): adds the display
///   name when the model is catalogued.
///
/// Both fall back gracefully for uncatalogued refs (passthrough) and for
/// the case where no active model is known yet (pre-config bootstrap).
library;

import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/catalog/model_ref.dart';

/// Compact one-line label for the status bar. Returns [fallback] when no
/// ref is available (e.g. before config finishes loading).
String formatStatusModelLabel(
  ModelRef? ref,
  ModelCatalog? catalog,
  String fallback,
) {
  if (ref == null) return fallback;
  final def = _lookupDef(ref, catalog);
  final apiId = def?.apiId ?? ref.modelId;
  return '${ref.providerId} · $apiId';
}

/// Multi-line label for `/info`: display name + wire address, or the ref
/// alone when the model isn't catalogued.
String formatInfoModelLabel(
  ModelRef? ref,
  ModelCatalog? catalog,
  String fallback,
) {
  if (ref == null) return fallback;
  final def = _lookupDef(ref, catalog);
  if (def != null) {
    return '${def.name} — ${ref.providerId}/${def.apiId}';
  }
  return ref.toString();
}

ModelDef? _lookupDef(ModelRef ref, ModelCatalog? catalog) {
  final provider = catalog?.providers[ref.providerId];
  return provider?.models[ref.modelId];
}
