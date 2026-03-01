import 'package:glue/src/config/constants.dart';
import 'package:glue/src/web/browser/browser_config.dart';

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

/// Supported OCR providers for scanned PDF fallback.
enum OcrProviderType { mistral, openai }

/// Configuration for PDF text extraction.
class PdfConfig {
  final int maxBytes;
  final int timeoutSeconds;
  final bool enableOcrFallback;
  final OcrProviderType ocrProvider;
  final String? mistralApiKey;
  final String mistralModel;
  final String? openaiApiKey;
  final String openaiModel;

  const PdfConfig({
    this.maxBytes = AppConstants.pdfMaxBytes,
    this.timeoutSeconds = AppConstants.pdfTimeoutSeconds,
    this.enableOcrFallback = true,
    this.ocrProvider = OcrProviderType.mistral,
    this.mistralApiKey,
    this.mistralModel = 'mistral-ocr-small',
    this.openaiApiKey,
    this.openaiModel = 'gpt-4.1-mini',
  });

  /// Whether OCR is available (has at least one API key configured).
  bool get hasOcrCredentials {
    if (ocrProvider == OcrProviderType.mistral) {
      return mistralApiKey != null && mistralApiKey!.isNotEmpty;
    }
    return openaiApiKey != null && openaiApiKey!.isNotEmpty;
  }
}

class WebConfig {
  final WebFetchConfig fetch;
  final WebSearchConfig search;
  final PdfConfig pdf;
  final BrowserConfig browser;

  const WebConfig({
    this.fetch = const WebFetchConfig(),
    this.search = const WebSearchConfig(),
    this.pdf = const PdfConfig(),
    this.browser = const BrowserConfig(),
  });
}
