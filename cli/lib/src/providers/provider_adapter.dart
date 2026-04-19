/// The single interface every LLM provider lives behind.
///
/// A [ProviderAdapter] answers three questions:
///   - Can this provider talk to anything? (`validate`)
///   - Give me a streaming client for this model. (`createClient`)
///   - Optionally: what models does this endpoint advertise? (`discoverModels`)
///
/// [discoverModels] is explicitly opt-in — never invoked during startup. Glue
/// prefers a curated, bundled catalog over live provider discovery.
library;

import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/resolved.dart';

enum ProviderHealth { ok, missingCredential, unknownAdapter }

class DiscoveredModel {
  const DiscoveredModel({required this.id, required this.name});

  final String id;
  final String name;
}

abstract class ProviderAdapter {
  String get adapterId;

  ProviderHealth validate(ResolvedProvider provider);

  LlmClient createClient({
    required ResolvedProvider provider,
    required ResolvedModel model,
    required String systemPrompt,
  });

  /// Only invoked by explicit user commands (e.g. `/models refresh`). Must
  /// never run during startup — Glue ships a curated catalog instead.
  Future<List<DiscoveredModel>> discoverModels(
      ResolvedProvider provider) async {
    return const [];
  }

  /// Produce the interactive flow the `/provider add` UI should display.
  ///
  /// Default implementation:
  ///   - [AuthKind.none] → returns null (nothing to do).
  ///   - [AuthKind.apiKey] → returns an [ApiKeyFlow] pre-filled from env.
  ///   - [AuthKind.oauth] → throws [UnimplementedError]; OAuth adapters
  ///     must override to drive a device-code or PKCE flow.
  Future<AuthFlow?> beginInteractiveAuth({
    required ProviderDef provider,
    required CredentialStore store,
  }) async {
    switch (provider.auth.kind) {
      case AuthKind.none:
        return null;
      case AuthKind.apiKey:
        final envVar = provider.auth.envVar;
        return ApiKeyFlow(
          providerId: provider.id,
          providerName: provider.name,
          envVar: envVar,
          envPresent: envVar != null ? store.readEnv(envVar) : null,
          helpUrl: provider.auth.helpUrl,
        );
      case AuthKind.oauth:
        throw UnimplementedError(
          'adapter "$adapterId" declares oauth but does not implement '
          'beginInteractiveAuth',
        );
    }
  }

  /// Is this provider connected (has usable credentials)?
  ///
  /// Default covers [AuthKind.none] (always true) and [AuthKind.apiKey]
  /// (env or stored `api_key` resolves). OAuth adapters must override.
  bool isConnected(ProviderDef provider, CredentialStore store) {
    switch (provider.auth.kind) {
      case AuthKind.none:
        return true;
      case AuthKind.apiKey:
        final resolved = store.resolveForProvider(provider);
        return resolved != null && resolved.isNotEmpty;
      case AuthKind.oauth:
        return false;
    }
  }
}

class AdapterRegistry {
  AdapterRegistry(Iterable<ProviderAdapter> adapters)
      : _byId = <String, ProviderAdapter>{} {
    for (final adapter in adapters) {
      if (_byId.containsKey(adapter.adapterId)) {
        throw ArgumentError(
          'duplicate adapter id: "${adapter.adapterId}"',
        );
      }
      _byId[adapter.adapterId] = adapter;
    }
  }

  final Map<String, ProviderAdapter> _byId;

  ProviderAdapter? lookup(String adapterId) => _byId[adapterId];

  Iterable<String> get registered => _byId.keys;
}
