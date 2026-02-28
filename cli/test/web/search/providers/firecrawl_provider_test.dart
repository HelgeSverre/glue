import 'dart:convert';

import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/firecrawl_provider.dart';

void main() {
  group('FirecrawlSearchProvider', () {
    test('isConfigured returns false without API key', () {
      final provider = FirecrawlSearchProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });

    test('isConfigured returns true with API key', () {
      final provider = FirecrawlSearchProvider(apiKey: 'fc-key');
      expect(provider.isConfigured, isTrue);
    });

    test('name is firecrawl', () {
      final provider = FirecrawlSearchProvider(apiKey: 'key');
      expect(provider.name, 'firecrawl');
    });

    test('parseResponse handles valid JSON', () {
      final json = jsonDecode('''{
        "success": true,
        "data": [
          {
            "title": "Firecrawl Result",
            "url": "https://example.com/fc",
            "description": "Content from Firecrawl.",
            "markdown": "# Full Content"
          }
        ]
      }''') as Map<String, dynamic>;

      final results = FirecrawlSearchProvider.parseResponse(json, 'test');
      expect(results.results, hasLength(1));
      expect(results.results[0].title, 'Firecrawl Result');
      expect(results.provider, 'firecrawl');
    });

    test('parseResponse handles empty data', () {
      final json = <String, dynamic>{
        'success': true,
        'data': <dynamic>[],
      };
      final results = FirecrawlSearchProvider.parseResponse(json, 'test');
      expect(results.results, isEmpty);
    });
  });
}
