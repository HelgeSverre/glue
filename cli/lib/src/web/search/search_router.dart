import 'package:glue/src/web/search/models.dart';
import 'package:glue/src/web/search/provider.dart';

class SearchRouter {
  final List<WebSearchProvider> providers;
  final Set<String> _freeFallbackProviders;

  SearchRouter(
    this.providers, {
    Set<String> freeFallbackProviders = const {'duckduckgo'},
  }) : _freeFallbackProviders = freeFallbackProviders;

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

    final configured = providers.where((p) => p.isConfigured).toList();
    final fallbackProviders = providers
        .where(
            (p) => !p.isConfigured && _freeFallbackProviders.contains(p.name))
        .toList();
    final available = [...configured, ...fallbackProviders];
    if (available.isEmpty) {
      throw StateError(
        'No search provider configured. Set one of: '
        'BRAVE_API_KEY, TAVILY_API_KEY, or FIRECRAWL_API_KEY',
      );
    }

    Exception? lastError;
    for (final provider in available) {
      try {
        return await provider.search(query, maxResults: maxResults);
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
        if (!fallback) rethrow;
      }
    }

    throw lastError!;
  }
}
