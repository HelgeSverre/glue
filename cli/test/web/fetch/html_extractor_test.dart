import 'package:test/test.dart';
import 'package:glue/src/web/fetch/html_extractor.dart';

void main() {
  group('HtmlExtractor', () {
    test('extracts article content from page', () {
      const html = '''
      <html><body>
        <nav><a href="/">Home</a><a href="/about">About</a></nav>
        <article>
          <h1>Hello World</h1>
          <p>This is the main content of the article.</p>
          <p>It has multiple paragraphs with useful information.</p>
        </article>
        <footer>Copyright 2026</footer>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Hello World'));
      expect(result, contains('main content'));
      expect(result, isNot(contains('Copyright')));
      expect(result, isNot(contains('Home')));
    });

    test('extracts main element when no article', () {
      const html = '''
      <html><body>
        <nav>Navigation</nav>
        <main><h1>Title</h1><p>Content here.</p></main>
        <aside>Sidebar</aside>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Title'));
      expect(result, contains('Content here'));
      expect(result, isNot(contains('Navigation')));
      expect(result, isNot(contains('Sidebar')));
    });

    test('falls back to body when no semantic containers', () {
      const html = '''
      <html><body>
        <h1>Simple Page</h1>
        <p>Just some text.</p>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Simple Page'));
      expect(result, contains('Just some text'));
    });

    test('strips script and style tags', () {
      const html = '''
      <html><body>
        <script>alert("bad")</script>
        <style>.x { color: red; }</style>
        <p>Clean content.</p>
      </body></html>
      ''';

      final result = HtmlExtractor.extract(html);
      expect(result, contains('Clean content'));
      expect(result, isNot(contains('alert')));
      expect(result, isNot(contains('color')));
    });

    test('returns empty string for empty/invalid HTML', () {
      expect(HtmlExtractor.extract(''), isEmpty);
      expect(HtmlExtractor.extract('not html at all'), isNotEmpty);
    });
  });
}
