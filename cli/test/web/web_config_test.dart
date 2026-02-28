import 'package:test/test.dart';
import 'package:glue/src/web/web_config.dart';

void main() {
  group('WebSearchConfig', () {
    test('resolvedProvider returns null when no keys set', () {
      const config = WebSearchConfig();
      expect(config.resolvedProvider, isNull);
    });

    test('resolvedProvider prefers brave over tavily', () {
      const config = WebSearchConfig(
        braveApiKey: 'key1',
        tavilyApiKey: 'key2',
      );
      expect(config.resolvedProvider, WebSearchProviderType.brave);
    });

    test('resolvedProvider falls back to tavily', () {
      const config = WebSearchConfig(tavilyApiKey: 'key');
      expect(config.resolvedProvider, WebSearchProviderType.tavily);
    });

    test('resolvedProvider falls back to firecrawl', () {
      const config = WebSearchConfig(firecrawlApiKey: 'key');
      expect(config.resolvedProvider, WebSearchProviderType.firecrawl);
    });

    test('explicit provider overrides auto-detection', () {
      const config = WebSearchConfig(
        provider: WebSearchProviderType.firecrawl,
        braveApiKey: 'key',
      );
      expect(config.resolvedProvider, WebSearchProviderType.firecrawl);
    });

    test('empty string key is treated as not set', () {
      const config = WebSearchConfig(braveApiKey: '');
      expect(config.resolvedProvider, isNull);
    });
  });

  group('WebFetchConfig', () {
    test('defaults are sensible', () {
      const config = WebFetchConfig();
      expect(config.timeoutSeconds, 30);
      expect(config.maxBytes, 5 * 1024 * 1024);
      expect(config.defaultMaxTokens, 50000);
      expect(config.allowJinaFallback, isTrue);
    });
  });
}
