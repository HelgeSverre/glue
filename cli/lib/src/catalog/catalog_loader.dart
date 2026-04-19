/// Merges the bundled model catalog with optional cached-remote and
/// user-local overlays.
///
/// Merge order (later wins):
///   bundled → cachedRemote → localOverrides
///
/// A provider-level overlay replaces the entire [ProviderDef] from earlier
/// sources. This keeps override semantics predictable: users can redefine a
/// provider by writing its full entry in `~/.glue/models.yaml`, and the local
/// copy is self-contained.
library;

import 'package:glue/src/catalog/model_catalog.dart';

ModelCatalog loadCatalog({
  required ModelCatalog bundled,
  ModelCatalog? cachedRemote,
  ModelCatalog? localOverrides,
}) {
  final layers = [
    bundled,
    if (cachedRemote != null) cachedRemote,
    if (localOverrides != null) localOverrides
  ];

  final capabilities = <String, String>{};
  final providers = <String, ProviderDef>{};
  var defaults = bundled.defaults;
  var version = bundled.version;
  var updatedAt = bundled.updatedAt;

  for (final layer in layers) {
    capabilities.addAll(layer.capabilities);
    providers.addAll(layer.providers);
    if (!identical(layer, bundled)) {
      defaults = layer.defaults;
      if (layer.version != 0) version = layer.version;
      if (layer.updatedAt.isNotEmpty) updatedAt = layer.updatedAt;
    }
  }

  return ModelCatalog(
    version: version,
    updatedAt: updatedAt,
    defaults: defaults,
    capabilities: capabilities,
    providers: providers,
  );
}
