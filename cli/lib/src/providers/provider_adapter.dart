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
