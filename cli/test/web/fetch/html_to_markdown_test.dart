import 'package:glue/src/web/fetch/html_to_markdown.dart';
import 'package:test/test.dart';

void main() {
  group('HtmlToMarkdown', () {
    test('converts headings', () {
      expect(HtmlToMarkdown.convert('<h1>Title</h1>'), '# Title\n');
      expect(HtmlToMarkdown.convert('<h2>Sub</h2>'), '## Sub\n');
      expect(HtmlToMarkdown.convert('<h3>H3</h3>'), '### H3\n');
    });

    test('converts paragraphs', () {
      expect(
        HtmlToMarkdown.convert('<p>Hello world.</p>'),
        'Hello world.\n',
      );
    });

    test('converts bold and italic', () {
      expect(
        HtmlToMarkdown.convert(
            '<p><strong>bold</strong> and <em>italic</em></p>'),
        '**bold** and *italic*\n',
      );
    });

    test('converts links', () {
      expect(
        HtmlToMarkdown.convert('<a href="https://example.com">click</a>'),
        '[click](https://example.com)\n',
      );
    });

    test('converts unordered lists', () {
      final result = HtmlToMarkdown.convert(
        '<ul><li>one</li><li>two</li></ul>',
      );
      expect(result, contains('- one'));
      expect(result, contains('- two'));
    });

    test('converts ordered lists', () {
      final result = HtmlToMarkdown.convert(
        '<ol><li>first</li><li>second</li></ol>',
      );
      expect(result, contains('1. first'));
      expect(result, contains('2. second'));
    });

    test('converts code blocks', () {
      final result = HtmlToMarkdown.convert(
        '<pre><code>var x = 1;</code></pre>',
      );
      expect(result, contains('```'));
      expect(result, contains('var x = 1;'));
    });

    test('converts inline code', () {
      expect(
        HtmlToMarkdown.convert('<p>Use <code>dart run</code> to start.</p>'),
        'Use `dart run` to start.\n',
      );
    });

    test('converts blockquotes', () {
      final result = HtmlToMarkdown.convert(
        '<blockquote><p>A wise quote.</p></blockquote>',
      );
      expect(result, contains('> A wise quote.'));
    });

    test('converts images', () {
      expect(
        HtmlToMarkdown.convert('<img src="pic.png" alt="photo">'),
        '![photo](pic.png)\n',
      );
    });

    test('converts horizontal rules', () {
      expect(
        HtmlToMarkdown.convert('<hr>'),
        contains('---'),
      );
    });

    test('handles nested elements', () {
      final result = HtmlToMarkdown.convert(
        '<p>Text with <strong><em>bold italic</em></strong> end.</p>',
      );
      expect(result, contains('***bold italic***'));
    });

    test('handles empty input', () {
      expect(HtmlToMarkdown.convert(''), isEmpty);
    });

    test('strips unknown tags but keeps text', () {
      expect(
        HtmlToMarkdown.convert('<div><span>hello</span></div>'),
        contains('hello'),
      );
    });
  });
}
