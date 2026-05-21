/// Merges the bundled model catalog with optional cached-remote and
/// user-local overlays.
///
/// Merge order (later wins): bundled → cachedRemote → localOverrides.
///
/// **Cached-remote** is field-merged onto bundled per provider. Remote
/// payloads pass through [sanitizeRemoteCatalogYaml] before they land in the
/// cache, which strips `base_url` / `request_headers` and clamps `auth` to
/// `{api_key: none}` as a defense against a hostile remote redirecting a
/// known provider's traffic. Whole-ProviderDef replacement would then wipe
/// out the bundled `auth: env:XXX_API_KEY` and `base_url`, breaking the
/// provider every time the user runs `glue catalog refresh`. Field-merging
/// preserves stripped fields from the bundled layer while still letting the
/// remote layer refresh `models`, `enabled`, `docs_url`, and `name`.
///
/// **Local overrides** retain whole-ProviderDef replace semantics. Users
/// writing `~/.glue/models.yaml` redeclare a provider in full, and the local
/// copy is self-contained — matching the long-standing documented contract.
library;

import 'package:glue_core/glue_core.dart';

ModelCatalog loadCatalog({
  required ModelCatalog bundled,
  ModelCatalog? cachedRemote,
  ModelCatalog? localOverrides,
}) {
  final capabilities = <String, String>{
    ...bundled.capabilities,
    if (cachedRemote != null) ...cachedRemote.capabilities,
    if (localOverrides != null) ...localOverrides.capabilities,
  };

  final providers = <String, ProviderDef>{...bundled.providers};

  if (cachedRemote != null) {
    for (final entry in cachedRemote.providers.entries) {
      final existing = providers[entry.key];
      providers[entry.key] = existing == null
          ? entry.value
          : _mergeProvider(base: existing, overlay: entry.value);
    }
  }

  if (localOverrides != null) {
    providers.addAll(localOverrides.providers);
  }

  var defaults = bundled.defaults;
  var version = bundled.version;
  var updatedAt = bundled.updatedAt;
  for (final layer in [
    if (cachedRemote != null) cachedRemote,
    if (localOverrides != null) localOverrides,
  ]) {
    defaults = layer.defaults;
    if (layer.version != 0) version = layer.version;
    if (layer.updatedAt.isNotEmpty) updatedAt = layer.updatedAt;
  }

  return ModelCatalog(
    version: version,
    updatedAt: updatedAt,
    defaults: defaults,
    capabilities: capabilities,
    providers: providers,
  );
}

/// Field-merge [overlay] onto [base]. Used for the cached-remote layer where
/// the sanitizer may have stripped fields — those land as null / empty /
/// default and fall back to the bundled value.
ProviderDef _mergeProvider({
  required ProviderDef base,
  required ProviderDef overlay,
}) {
  return ProviderDef(
    id: base.id,
    name: overlay.name.isNotEmpty ? overlay.name : base.name,
    adapter: overlay.adapter.isNotEmpty ? overlay.adapter : base.adapter,
    compatibility: overlay.compatibility ?? base.compatibility,
    enabled: overlay.enabled,
    baseUrl: overlay.baseUrl ?? base.baseUrl,
    docsUrl: overlay.docsUrl ?? base.docsUrl,
    auth: _isDefaultedAuth(overlay.auth) ? base.auth : overlay.auth,
    requestHeaders: overlay.requestHeaders.isEmpty
        ? base.requestHeaders
        : overlay.requestHeaders,
    models: overlay.models.isEmpty ? base.models : overlay.models,
  );
}

/// `true` when [auth] carries no information beyond the sanitizer's
/// post-strip default (`AuthKind.none`, no env var, no help URL). The
/// loader treats this as "no overlay information available — keep bundled".
bool _isDefaultedAuth(AuthSpec auth) =>
    auth.kind == AuthKind.none && auth.envVar == null && auth.helpUrl == null;
