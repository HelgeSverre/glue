import '../config/constants.dart';

class WebFetchConfig {
  final int timeoutSeconds;
  final int maxBytes;
  final int defaultMaxTokens;
  final String? jinaApiKey;
  final String jinaBaseUrl;
  final bool allowJinaFallback;

  const WebFetchConfig({
    this.timeoutSeconds = AppConstants.webFetchTimeoutSeconds,
    this.maxBytes = AppConstants.webFetchMaxBytes,
    this.defaultMaxTokens = AppConstants.webFetchDefaultMaxTokens,
    this.jinaApiKey,
    this.jinaBaseUrl = 'https://r.jina.ai',
    this.allowJinaFallback = true,
  });
}

enum WebSearchProviderType { brave, tavily, firecrawl }

class WebSearchConfig {
  final WebSearchProviderType? provider;
  final int timeoutSeconds;
  final int defaultMaxResults;
  final String? braveApiKey;
  final String? tavilyApiKey;
  final String? firecrawlApiKey;
  final String? firecrawlBaseUrl;

  const WebSearchConfig({
    this.provider,
    this.timeoutSeconds = AppConstants.webSearchTimeoutSeconds,
    this.defaultMaxResults = AppConstants.webSearchDefaultMaxResults,
    this.braveApiKey,
    this.tavilyApiKey,
    this.firecrawlApiKey,
    this.firecrawlBaseUrl,
  });

  /// Auto-detect provider from available API keys.
  /// Priority: brave → tavily → firecrawl.
  WebSearchProviderType? get resolvedProvider {
    if (provider != null) return provider;
    if (braveApiKey != null && braveApiKey!.isNotEmpty) {
      return WebSearchProviderType.brave;
    }
    if (tavilyApiKey != null && tavilyApiKey!.isNotEmpty) {
      return WebSearchProviderType.tavily;
    }
    if (firecrawlApiKey != null && firecrawlApiKey!.isNotEmpty) {
      return WebSearchProviderType.firecrawl;
    }
    return null;
  }
}

class WebConfig {
  final WebFetchConfig fetch;
  final WebSearchConfig search;

  const WebConfig({
    this.fetch = const WebFetchConfig(),
    this.search = const WebSearchConfig(),
  });
}
