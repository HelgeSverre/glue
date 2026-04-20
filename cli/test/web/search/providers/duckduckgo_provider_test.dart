import 'package:test/test.dart';
import 'package:glue/src/web/search/providers/duckduckgo_provider.dart';

void main() {
  group('DuckDuckGoSearchProvider', () {
    test('isConfigured returns true without API key', () {
      final provider = DuckDuckGoSearchProvider();
      expect(provider.isConfigured, isTrue);
    });

    test('name is duckduckgo', () {
      final provider = DuckDuckGoSearchProvider();
      expect(provider.name, 'duckduckgo');
    });

    test('parseHtml extracts results from html anchors', () {
      const html = '''
<html>
  <body>
    <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpost">Example Result</a>
    <a class="result__snippet">Example snippet text.</a>
    <a class="result__a" href="https://example.org/plain">Plain Result</a>
    <a class="result__snippet">Another snippet.</a>
  </body>
</html>
''';

      final results = DuckDuckGoSearchProvider.parseHtml(html, 'test query');

      expect(results.provider, 'duckduckgo');
      expect(results.query, 'test query');
      expect(results.results, hasLength(2));
      expect(results.results[0].title, 'Example Result');
      expect(results.results[0].url.toString(), 'https://example.com/post');
      expect(results.results[0].snippet, 'Example snippet text.');
      expect(results.results[1].title, 'Plain Result');
      expect(results.results[1].url.toString(), 'https://example.org/plain');
      expect(results.results[1].snippet, 'Another snippet.');
    });

    test('parseHtml handles empty html', () {
      final results = DuckDuckGoSearchProvider.parseHtml('', 'test');
      expect(results.results, isEmpty);
    });
  });
}
