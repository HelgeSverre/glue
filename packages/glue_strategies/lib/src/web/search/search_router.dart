import 'package:glue_strategies/src/web/search/models.dart';
import 'package:glue_strategies/src/web/search/provider.dart';

class SearchRouter {
  final List<WebSearchProvider> providers;
  final Set<String> _freeFallbackProviders;

  SearchRouter(
    this.providers, {
    this._freeFallbackProviders = const {'duckduckgo'},
  });

  WebSearchProvider? get defaultProvider {
    for (final p in providers) {
      if (p.isConfigured) return p;
    }
    for (final p in providers) {
      if (_freeFallbackProviders.contains(p.name)) return p;
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
        'No search provider configured. Set one of: '
        'BRAVE_API_KEY, TAVILY_API_KEY, or FIRECRAWL_API_KEY',
      );
    }

    if (!fallback) {
      return defaultP.search(query, maxResults: maxResults);
    }

    // Try configured providers first, then free fallbacks, with fallback.
    final available = [
      defaultP,
      ...providers.where(
        (p) => p != defaultP && (p.isConfigured || _freeFallbackProviders.contains(p.name)),
      ),
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
