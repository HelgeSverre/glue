import 'dart:convert';

import 'package:glue/src/web/search/providers/brave_provider.dart';
import 'package:test/test.dart';

void main() {
  group('BraveSearchProvider', () {
    test('isConfigured returns false without API key', () {
      final provider = BraveSearchProvider(apiKey: null);
      expect(provider.isConfigured, isFalse);
    });

    test('isConfigured returns true with API key', () {
      final provider = BraveSearchProvider(apiKey: 'test-key');
      expect(provider.isConfigured, isTrue);
    });

    test('name is brave', () {
      final provider = BraveSearchProvider(apiKey: 'key');
      expect(provider.name, 'brave');
    });

    test('parseResponse handles valid JSON', () {
      final json = jsonDecode('''{
        "web": {
          "results": [
            {
              "title": "Test Page",
              "url": "https://example.com",
              "description": "A test page description."
            },
            {
              "title": "Another Page",
              "url": "https://example.org",
              "description": "Another description."
            }
          ]
        }
      }''') as Map<String, dynamic>;

      final results = BraveSearchProvider.parseResponse(json, 'test');
      expect(results.results, hasLength(2));
      expect(results.results[0].title, 'Test Page');
      expect(results.results[0].url.host, 'example.com');
      expect(results.results[1].snippet, 'Another description.');
      expect(results.provider, 'brave');
    });

    test('parseResponse handles empty results', () {
      final json = <String, dynamic>{
        'web': {'results': <dynamic>[]},
      };
      final results = BraveSearchProvider.parseResponse(json, 'test');
      expect(results.results, isEmpty);
    });

    test('parseResponse handles missing web key', () {
      final results = BraveSearchProvider.parseResponse({}, 'test');
      expect(results.results, isEmpty);
    });
  });
}
