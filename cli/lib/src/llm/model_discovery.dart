import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:glue/src/config/glue_config.dart';
import 'package:glue/src/config/model_registry.dart';
import 'package:glue/src/llm/model_lister.dart';

/// Discovers models from all configured providers with disk caching.
class ModelDiscovery {
  final String cacheDir;
  final ModelLister _lister;

  static const _cacheDuration = Duration(hours: 6);

  ModelDiscovery({required this.cacheDir, ModelLister? lister})
      : _lister = lister ?? ModelLister();

  /// Discovers models from all configured providers, merges with registry.
  ///
  /// Registry entries win on ID collision. Results are sorted by provider
  /// order, with registry entries first per group.
  Future<List<ModelEntry>> discoverAll(GlueConfig config) async {
    final providers = _configuredProviders(config);
    final futures = <Future<List<ModelInfo>>>[];
    final providerOrder = <LlmProvider>[];
    final staleCache = <LlmProvider, List<ModelInfo>>{};

    for (final provider in providers) {
      final cached = _readCache(provider);
      if (cached != null && _isFresh(cached)) {
        // Fresh cache — use directly, no fetch needed.
        staleCache[provider] = _parseModels(cached);
        providerOrder.add(provider);
        futures.add(Future.value(staleCache[provider]));
      } else {
        // Stale or missing — fetch, but keep stale as fallback.
        if (cached != null) {
          staleCache[provider] = _parseModels(cached);
        }
        providerOrder.add(provider);
        futures.add(_fetch(provider, config).then((models) {
          _writeCache(provider, models);
          return models;
        }).catchError((Object _) {
          // On failure, fall back to stale cache or empty.
          return staleCache[provider] ?? <ModelInfo>[];
        }));
      }
    }

    final results = await Future.wait(futures);

    // Build discovered ModelEntry objects.
    final discovered = <ModelEntry>[];
    for (var i = 0; i < providerOrder.length; i++) {
      final provider = providerOrder[i];
      for (final model in results[i]) {
        discovered.add(_toEntry(model, provider));
      }
    }

    // Merge with registry — registry entries win on ID collision.
    final registry = ModelRegistry.available(config);
    final registryIds = registry.map((e) => e.modelId).toSet();
    final extra =
        discovered.where((e) => !registryIds.contains(e.modelId)).toList();

    // Sort: group by provider order, registry entries first per group.
    final merged = <ModelEntry>[];
    for (final provider in LlmProvider.values) {
      final reg = registry.where((e) => e.provider == provider);
      final disc = extra.where((e) => e.provider == provider);
      merged.addAll(reg);
      merged.addAll(disc);
    }
    return merged;
  }

  /// Providers that have credentials configured (Ollama always included).
  List<LlmProvider> _configuredProviders(GlueConfig config) {
    return LlmProvider.values.where((provider) {
      return switch (provider) {
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

  Future<List<ModelInfo>> _fetch(LlmProvider provider, GlueConfig config) {
    final apiKey = switch (provider) {
      LlmProvider.anthropic => config.anthropicApiKey,
      LlmProvider.openai => config.openaiApiKey,
      LlmProvider.mistral => config.mistralApiKey,
      LlmProvider.ollama => null,
    };
    return _lister.list(
      provider: provider,
      apiKey: apiKey,
      ollamaBaseUrl: config.ollamaBaseUrl,
    );
  }

  ModelEntry _toEntry(ModelInfo model, LlmProvider provider) {
    if (provider == LlmProvider.ollama) {
      final displayName = _stripLatest(model.id);
      final tagline =
          model.size != null ? 'Local \u00b7 ${model.size}' : 'Local model';
      return ModelEntry(
        displayName: displayName,
        modelId: model.id,
        provider: LlmProvider.ollama,
        capabilities: const {ModelCapability.coding},
        cost: CostTier.free,
        speed: SpeedTier.fast,
        tagline: tagline,
      );
    }
    final providerLabel = switch (provider) {
      LlmProvider.anthropic => 'Anthropic',
      LlmProvider.openai => 'OpenAI',
      LlmProvider.mistral => 'Mistral',
      LlmProvider.ollama => 'Ollama',
    };
    return ModelEntry(
      displayName: model.id,
      modelId: model.id,
      provider: provider,
      capabilities: const {ModelCapability.coding},
      cost: CostTier.medium,
      speed: SpeedTier.standard,
      tagline: '$providerLabel API',
    );
  }

  static String _stripLatest(String name) {
    return name.endsWith(':latest') ? name.substring(0, name.length - 7) : name;
  }

  // ── Cache I/O ──────────────────────────────────────────────────

  String _cachePath(LlmProvider provider) =>
      p.join(cacheDir, 'models_${provider.name}.json');

  Map<String, dynamic>? _readCache(LlmProvider provider) {
    final file = File(_cachePath(provider));
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool _isFresh(Map<String, dynamic> cache) {
    final ts = cache['fetched_at'] as String?;
    if (ts == null) return false;
    final fetched = DateTime.tryParse(ts);
    if (fetched == null) return false;
    return DateTime.now().toUtc().difference(fetched) < _cacheDuration;
  }

  List<ModelInfo> _parseModels(Map<String, dynamic> cache) {
    final models = cache['models'] as List? ?? [];
    return models.map((m) {
      final map = m as Map<String, dynamic>;
      return ModelInfo(
        id: map['id'] as String? ?? '',
        size: map['size'] as String?,
      );
    }).toList();
  }

  void _writeCache(LlmProvider provider, List<ModelInfo> models) {
    try {
      final dir = Directory(cacheDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final data = jsonEncode({
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
        'models': models
            .map((m) => {
                  'id': m.id,
                  if (m.size != null) 'size': m.size,
                })
            .toList(),
      });
      final tmp = File('${_cachePath(provider)}.tmp');
      tmp.writeAsStringSync(data);
      tmp.renameSync(_cachePath(provider));
    } catch (_) {
      // Cache write failure is non-fatal.
    }
  }
}
