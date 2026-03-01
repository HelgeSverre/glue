import 'dart:convert';

import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/tavily_provider.dart';

void main() {
  group('TavilySearchProvider', () {
    test('isConfigured returns false without API key', () {
      final provider = TavilySearchProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });

    test('isConfigured returns true with API key', () {
      final provider = TavilySearchProvider(apiKey: 'tvly-key');
      expect(provider.isConfigured, isTrue);
    });

    test('name is tavily', () {
      final provider = TavilySearchProvider(apiKey: 'key');
      expect(provider.name, 'tavily');
    });

    test('parseResponse handles valid JSON', () {
      final json = jsonDecode('''{
        "query": "test",
        "results": [
          {
            "title": "Tavily Result",
            "url": "https://example.com/tavily",
            "content": "Detailed content from Tavily."
          }
        ],
        "answer": "AI-generated summary."
      }''') as Map<String, dynamic>;

      final results = TavilySearchProvider.parseResponse(json);
      expect(results.results, hasLength(1));
      expect(results.results[0].title, 'Tavily Result');
      expect(results.aiSummary, 'AI-generated summary.');
      expect(results.provider, 'tavily');
    });

    test('parseResponse handles missing answer', () {
      final json = <String, dynamic>{
        'query': 'test',
        'results': <dynamic>[],
      };
      final results = TavilySearchProvider.parseResponse(json);
      expect(results.aiSummary, isNull);
    });
  });
}
