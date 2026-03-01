import 'package:test/test.dart';
import 'package:glue/src/web/search/models.dart';

void main() {
  group('WebSearchResult', () {
    test('creates with all fields', () {
      final result = WebSearchResult(
        title: 'Test',
        url: Uri.parse('https://example.com'),
        snippet: 'A snippet',
      );
      expect(result.title, 'Test');
      expect(result.url.host, 'example.com');
      expect(result.snippet, 'A snippet');
    });

    test('formats as readable text', () {
      final result = WebSearchResult(
        title: 'Page Title',
        url: Uri.parse('https://example.com/page'),
        snippet: 'Description of the page.',
      );
      final text = result.toText();
      expect(text, contains('Page Title'));
      expect(text, contains('https://example.com/page'));
      expect(text, contains('Description'));
    });
  });

  group('WebSearchResponse', () {
    test('formats results as text', () {
      final response = WebSearchResponse(
        provider: 'brave',
        query: 'test query',
        results: [
          WebSearchResult(
            title: 'Result 1',
            url: Uri.parse('https://r1.com'),
            snippet: 'First result.',
          ),
          WebSearchResult(
            title: 'Result 2',
            url: Uri.parse('https://r2.com'),
            snippet: 'Second result.',
          ),
        ],
      );
      final text = response.toText();
      expect(text, contains('Result 1'));
      expect(text, contains('Result 2'));
      expect(text, contains('brave'));
    });

    test('empty results produce clear message', () {
      const response = WebSearchResponse(
        provider: 'brave',
        query: 'nothing',
        results: [],
      );
      expect(response.toText(), contains('No results'));
    });
  });
}
