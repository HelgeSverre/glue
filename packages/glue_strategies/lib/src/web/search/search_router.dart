import 'package:glue_strategies/src/web/search/models.dart';
import 'package:glue_strategies/src/web/search/provider.dart';

class SearchRouter {
  final List<WebSearchProvider> providers;

  SearchRouter(this.providers);

  /// The first provider that reports itself usable.
  ///
  /// Keyless providers say so through [WebSearchProvider.isConfigured] —
  /// DuckDuckGo returns true unconditionally — so there is no separate
  /// "free fallback" tier.
  WebSearchProvider? get defaultProvider {
    for (final p in providers) {
      if (p.isConfigured) return p;
    }
    return null;
  }

  Future<WebSearchResponse> search(
    String query, {
    int maxResults = 5,
    String? providerName,
    bool fallback = true,
  }) async {
    if (providerName != null) {
      final provider = providers.firstWhere(
        (p) => p.name == providerName && p.isConfigured,
        orElse: () => throw StateError(
          'Search provider "$providerName" not found or not configured',
        ),
      );
      return provider.search(query, maxResults: maxResults);
    }

    final defaultP = defaultProvider;
    if (defaultP == null) {
      throw StateError(
        'No usable search provider. DuckDuckGo needs no key, so this means '
        'the router was built with no providers at all.',
      );
    }

    if (!fallback) {
      return defaultP.search(query, maxResults: maxResults);
    }

    final available = [
      defaultP,
      ...providers.where((p) => p != defaultP && p.isConfigured),
    ];

    Exception? lastError;
    for (final provider in available) {
      try {
        return await provider.search(query, maxResults: maxResults);
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
      }
    }

    throw lastError!;
  }
}
