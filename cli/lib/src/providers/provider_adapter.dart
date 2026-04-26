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

import 'package:glue/src/agent/agent.dart';
import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/credentials/credential_store.dart';
import 'package:glue/src/providers/auth_flow.dart';
import 'package:glue/src/providers/resolved.dart';

enum ProviderHealth {
  /// Probe accepted — the credential authenticates against the provider.
  ok,

  /// No credential resolved (env unset, nothing stored).
  missingCredential,

  /// Server rejected the credential (HTTP 401/403, or provider-specific
  /// equivalents like Gemini's `API_KEY_INVALID`).
  unauthorized,

  /// Couldn't determine — network error, timeout, or 5xx. Distinct from
  /// [unauthorized] so callers can decide whether to block (bad key) or
  /// proceed offline (down service / no network).
  unreachable,

  /// No adapter registered for the provider's wire protocol.
  unknownAdapter,
}

class DiscoveredModel {
  const DiscoveredModel({required this.id, required this.name});

  final String id;
  final String name;
}

abstract class ProviderAdapter {
  String get adapterId;

  /// In-memory health check — does this provider have a usable credential
  /// in hand? Cheap, synchronous, no network. Use [probe] to actually verify
  /// the credential against the API.
  ProviderHealth validate(ResolvedProvider provider);

  /// Network probe — does the API accept this credential right now?
  ///
  /// Issues a single cheap, auth-required request (typically `GET /models`)
  /// and classifies the result:
  ///   - 200 → [ProviderHealth.ok]
  ///   - 401/403 / API_KEY_INVALID → [ProviderHealth.unauthorized]
  ///   - timeout / network error / 5xx → [ProviderHealth.unreachable]
  ///   - missing credential up front → [ProviderHealth.missingCredential]
  ///
  /// Default implementation falls back to [validate] (no network). Adapters
  /// that can probe should override.
  Future<ProviderHealth> probe(
    ResolvedProvider provider, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return validate(provider);
  }

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
