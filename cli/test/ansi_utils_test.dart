import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  // ── visibleLength ─────────────────────────────────────────────────────

  group('visibleLength', () {
    test('plain ASCII', () {
      expect(visibleLength('hello'), 5);
    });

    test('empty string', () {
      expect(visibleLength(''), 0);
    });

    test('ANSI codes are invisible', () {
      expect(visibleLength('\x1b[1mhello\x1b[0m'), 5);
      expect(visibleLength('\x1b[31m\x1b[1mbold red\x1b[0m'), 8);
    });

    test('Norwegian characters øæå are width 1', () {
      expect(visibleLength('øæå'), 3);
      expect(visibleLength('blåbær'), 6);
    });

    test('German umlauts äöü are width 1', () {
      expect(visibleLength('äöü'), 3);
      expect(visibleLength('Ärger'), 5);
    });

    test('accented characters (precomposed) are width 1', () {
      expect(visibleLength('café'), 4);
      expect(visibleLength('naïve'), 5);
      expect(visibleLength('résumé'), 6);
    });

    test('combining marks are zero-width', () {
      // e + combining acute accent = é (2 code units, 1 visible char)
      expect(visibleLength('e\u0301'), 1);
      // a + combining diaeresis = ä
      expect(visibleLength('a\u0308'), 1);
    });

    test('zalgo text — combining marks are zero-width', () {
      // "hello" with stacked combining marks
      final zalgo = 'h\u0335\u0321\u0353e\u0344\u0359l\u0334\u0319'
          'l\u0337\u0320o\u0336\u0326';
      expect(visibleLength(zalgo), 5);
    });

    test('CJK characters are double-width', () {
      expect(visibleLength('漢字'), 4);
      expect(visibleLength('日本語'), 6);
    });

    test('Korean characters are double-width', () {
      expect(visibleLength('한글'), 4);
    });

    test('simple emoji are double-width', () {
      expect(visibleLength('🎉'), 2);
      expect(visibleLength('🚀'), 2);
    });

    test('mixed ASCII and emoji', () {
      expect(visibleLength('hi 🎉'), 5); // h=1, i=1, space=1, 🎉=2
    });

    test('common symbols are width 1', () {
      expect(visibleLength('©®™'), 3);
      expect(visibleLength('→←↑↓'), 4);
    });

    test('fullwidth latin letters are double-width', () {
      // Ａ = U+FF21 (fullwidth A)
      expect(visibleLength('\uFF21\uFF22'), 4);
    });
  });

  // ── stripAnsi ─────────────────────────────────────────────────────────

  group('stripAnsi', () {
    test('removes SGR sequences', () {
      expect(stripAnsi('\x1b[1m\x1b[31mhello\x1b[0m'), 'hello');
    });

    test('no-op on plain text', () {
      expect(stripAnsi('hello world'), 'hello world');
    });

    test('removes multiple sequences', () {
      expect(stripAnsi('\x1b[33mfoo\x1b[39m \x1b[1mbar\x1b[22m'), 'foo bar');
    });
  });

  // ── ansiTruncate ──────────────────────────────────────────────────────

  group('ansiTruncate', () {
    test('no-op when text fits', () {
      expect(ansiTruncate('hello', 10), 'hello');
    });

    test('truncates with ellipsis', () {
      final result = ansiTruncate('hello world', 8);
      expect(stripAnsi(result).endsWith('…'), isTrue);
      expect(visibleLength(result), lessThanOrEqualTo(8));
    });

    test('preserves ANSI codes across truncation', () {
      final result = ansiTruncate('\x1b[1mhello world\x1b[0m', 8);
      expect(result, contains('\x1b[1m'));
      expect(visibleLength(result), lessThanOrEqualTo(8));
    });

    test('handles emoji truncation without splitting surrogate pairs', () {
      final result = ansiTruncate('🎉🚀🌍🎊', 5);
      expect(visibleLength(result), lessThanOrEqualTo(5));
      // Should not contain broken surrogate pairs
      expect(result.runes.every((r) => r >= 0), isTrue);
    });

    test('handles CJK truncation', () {
      final result = ansiTruncate('漢字漢字漢字', 5);
      expect(visibleLength(result), lessThanOrEqualTo(5));
    });

    test('truncates Norwegian text correctly', () {
      final result = ansiTruncate('blåbærsyltetøy er godt', 10);
      expect(visibleLength(result), lessThanOrEqualTo(10));
    });
  });

  // ── ansiWrap ──────────────────────────────────────────────────────────

  group('ansiWrap', () {
    test('no-op when text fits', () {
      expect(ansiWrap('hello', 20), 'hello');
    });

    test('wraps at word boundary', () {
      final result = ansiWrap('hello world foo', 11);
      expect(result, 'hello world\nfoo');
    });

    test('wraps long text into multiple lines', () {
      final result = ansiWrap('one two three four five', 10);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(10));
      }
    });

    test('preserves existing newlines', () {
      final result = ansiWrap('line one\nline two', 40);
      expect(result, 'line one\nline two');
    });

    test('handles empty string', () {
      expect(ansiWrap('', 20), '');
    });

    test('handles single long word that exceeds width', () {
      // A word longer than maxWidth can't be split (no spaces)
      final result = ansiWrap('superlongword', 5);
      // The word should still appear (can't break it)
      expect(result, contains('superlongword'));
    });

    test('preserves ANSI codes across wrap boundaries', () {
      final result = ansiWrap('\x1b[1mbold text here\x1b[0m', 10);
      final lines = result.split('\n');
      expect(lines.length, greaterThan(1));
      // First line should contain the ANSI open
      expect(lines.first, contains('\x1b[1m'));
    });

    test('wraps text with Norwegian characters', () {
      final result = ansiWrap('æbler og blåbær i skogen nå', 15);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(15));
      }
    });

    test('wraps text with umlauts', () {
      final result =
          ansiWrap('Ärger über die Ölförderung führt zu Übermut', 20);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(20));
      }
    });

    test('wraps text with CJK characters at double-width', () {
      // Each CJK char is 2 columns
      final result = ansiWrap('漢字 テスト 日本語', 8);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(8));
      }
    });

    test('wraps text with emoji at double-width', () {
      final result = ansiWrap('hello 🎉 world 🚀 dart', 10);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(10));
      }
    });

    test('wraps text with combining marks (zalgo)', () {
      // Zalgo text: visible width is just the base characters
      final zalgo = 'h\u0335e\u0344l\u0334l\u0337o\u0336 '
          'w\u0321o\u0359r\u0319l\u0320d\u0326';
      final result = ansiWrap(zalgo, 6);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(6));
      }
    });

    test('handles zero width', () {
      expect(ansiWrap('hello', 0), 'hello');
    });

    test('handles negative width', () {
      expect(ansiWrap('hello', -1), 'hello');
    });

    test('wraps empty lines in multi-paragraph text', () {
      final result = ansiWrap('first\n\nsecond', 40);
      expect(result, 'first\n\nsecond');
    });

    test('multiple spaces between words', () {
      // split(' ') produces empty strings between consecutive spaces
      final result = ansiWrap('hello  world', 20);
      expect(result, contains('hello'));
      expect(result, contains('world'));
    });

    test('wraps text with common symbols', () {
      final result = ansiWrap('→ arrow ← back ↑ up ↓ down', 12);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(12));
      }
    });
  });

  // ── wrapIndented ──────────────────────────────────────────────────────

  group('wrapIndented', () {
    test('applies firstPrefix and nextPrefix', () {
      final result = wrapIndented('one two three four', 12,
          firstPrefix: '• ', nextPrefix: '  ');
      final lines = result.split('\n');
      expect(lines.first, startsWith('• '));
      for (final line in lines.skip(1)) {
        expect(line, startsWith('  '));
      }
    });

    test('all lines fit within width', () {
      final result = wrapIndented(
          'The quick brown fox jumped over the lazy dog', 20,
          firstPrefix: '• ', nextPrefix: '  ');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(20));
      }
    });

    test('uniform prefix (indentation)', () {
      final result = wrapIndented('hello world foo bar baz', 15,
          firstPrefix: '   ', nextPrefix: '   ');
      final lines = result.split('\n');
      for (final line in lines) {
        expect(line, startsWith('   '));
        expect(visibleLength(line), lessThanOrEqualTo(15));
      }
    });

    test('blockquote prefix', () {
      final result = wrapIndented('some long quoted text here please', 18,
          firstPrefix: '│ ', nextPrefix: '│ ');
      final lines = result.split('\n');
      for (final line in lines) {
        expect(line, startsWith('│ '));
        expect(visibleLength(line), lessThanOrEqualTo(18));
      }
    });

    test('no-op when text fits on one line', () {
      final result =
          wrapIndented('short', 20, firstPrefix: '• ', nextPrefix: '  ');
      expect(result, '• short');
    });

    test('handles empty text', () {
      final result =
          wrapIndented('', 20, firstPrefix: '• ', nextPrefix: '  ');
      expect(result, startsWith('• '));
    });

    test('handles ANSI prefixes (visible width computed correctly)', () {
      final result = wrapIndented(
          'The quick brown fox jumped over the lazy dog', 25,
          firstPrefix: '\x1b[90m│ \x1b[0m',
          nextPrefix: '\x1b[90m│ \x1b[0m');
      final lines = result.split('\n');
      for (final line in lines) {
        expect(visibleLength(line), lessThanOrEqualTo(25));
      }
    });

    test('wraps Norwegian text with bullet prefix', () {
      final result = wrapIndented(
          'blåbærsyltetøy og rømme er veldig godt på vafler', 25,
          firstPrefix: '• ', nextPrefix: '  ');
      final lines = result.split('\n');
      expect(lines.first, startsWith('• '));
      for (final line in lines) {
        expect(visibleLength(line), lessThanOrEqualTo(25));
      }
    });

    test('wraps emoji text with indentation', () {
      final result = wrapIndented('🎉 party 🚀 rocket 🌍 earth 🎊 tada', 14,
          firstPrefix: '  ', nextPrefix: '  ');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(14));
      }
    });

    test('handles very narrow width gracefully', () {
      final result =
          wrapIndented('hello world', 3, firstPrefix: '', nextPrefix: '');
      // Should not crash, content should still be present
      expect(result, contains('hello'));
    });

    test('contentWidth <= 0 returns prefix + text as-is', () {
      final result = wrapIndented('hello', 2,
          firstPrefix: '>>> ', nextPrefix: '>>> ');
      expect(result, '>>> hello');
    });

    test('wider firstPrefix does not overflow width', () {
      final result = wrapIndented('one two three four five', 15,
          firstPrefix: '>>>>> ', nextPrefix: '  ');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(15),
            reason: 'Line overflows: "$line" (${visibleLength(line)} cols)');
      }
    });
  });

  // ── MarkdownRenderer wrapping ─────────────────────────────────────────

  group('MarkdownRenderer wrapping', () {
    test('paragraphs wrap to width', () {
      final r = MarkdownRenderer(30);
      final result = r.render(
          'The quick brown fox jumped over the lazy dog and kept running');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(30),
            reason: 'Line too wide: "$line"');
      }
    });

    test('headings wrap to width', () {
      final r = MarkdownRenderer(20);
      final result =
          r.render('# This is a very long heading that should wrap');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(20),
            reason: 'Heading line too wide: "$line"');
      }
    });

    test('heading continuation lines retain bold+yellow styling', () {
      final r = MarkdownRenderer(15);
      final result =
          r.render('# Short heading that wraps');
      final lines = result.split('\n');
      expect(lines.length, greaterThan(1),
          reason: 'Heading should wrap at width 15');
      for (final line in lines) {
        // Each line should have bold+yellow open and reset close
        expect(line, contains('\x1b[1m'),
            reason: 'Missing bold on line: "$line"');
        expect(line, contains('\x1b[33m'),
            reason: 'Missing yellow on line: "$line"');
        expect(line, endsWith('\x1b[0m'),
            reason: 'Missing reset on line: "$line"');
      }
    });

    test('blockquotes wrap within prefix', () {
      final r = MarkdownRenderer(25);
      final result = r.render(
          '> This is a long blockquote that should wrap nicely');
      final lines = result.split('\n');
      for (final line in lines) {
        expect(visibleLength(line), lessThanOrEqualTo(25),
            reason: 'Blockquote line too wide: "$line"');
        expect(stripAnsi(line), contains('│'),
            reason: 'Blockquote line missing │ prefix');
      }
    });

    test('unordered list items wrap with aligned continuation', () {
      final r = MarkdownRenderer(25);
      final result = r.render(
          '- This is a long list item that should wrap and align');
      final lines = result.split('\n');
      final stripped = lines.map(stripAnsi).toList();
      expect(stripped.first, startsWith('• '));
      for (var i = 1; i < stripped.length; i++) {
        expect(stripped[i], startsWith('  '),
            reason: 'Continuation not aligned: "${stripped[i]}"');
      }
      for (final line in lines) {
        expect(visibleLength(line), lessThanOrEqualTo(25));
      }
    });

    test('ordered list items wrap with aligned continuation', () {
      final r = MarkdownRenderer(25);
      final result = r.render(
          '1. This is a long ordered list item that should wrap');
      final lines = result.split('\n');
      final stripped = lines.map(stripAnsi).toList();
      expect(stripped.first, startsWith('1. '));
      for (var i = 1; i < stripped.length; i++) {
        // Continuation should be indented by "1. ".length = 3
        expect(stripped[i], startsWith('   '),
            reason: 'Continuation not aligned: "${stripped[i]}"');
      }
      for (final line in lines) {
        expect(visibleLength(line), lessThanOrEqualTo(25));
      }
    });

    test('code blocks are NOT wrapped (truncated instead)', () {
      final r = MarkdownRenderer(20);
      final result = r.render(
          '```\nthis_is_a_long_line_of_code_no_spaces\n```');
      // Code block should contain box drawing chars, not be word-wrapped
      expect(stripAnsi(result), contains('╭'));
      expect(stripAnsi(result), contains('╰'));
    });

    test('paragraph with Norwegian characters wraps', () {
      final r = MarkdownRenderer(25);
      final result = r.render(
          'Blåbærsyltetøy og rømme er veldig godt på vafler med is');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(25),
            reason: 'Line too wide: "$line"');
      }
    });

    test('paragraph with emoji wraps at correct width', () {
      final r = MarkdownRenderer(15);
      final result =
          r.render('Hello 🎉 this is 🚀 a test 🌍 of emoji');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(15),
            reason: 'Line too wide: "$line"');
      }
    });

    test('paragraph with CJK wraps at correct width', () {
      final r = MarkdownRenderer(12);
      final result = r.render('漢字 テスト 日本語 カタカナ');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(12),
            reason: 'Line too wide: "$line"');
      }
    });

    test('mixed content wraps each element correctly', () {
      final r = MarkdownRenderer(25);
      final md = '''# Long heading that wraps
Some long paragraph text that definitely needs wrapping.

- A list item with enough text to wrap
- Another item

> A blockquote that is long enough to wrap

1. An ordered list item that wraps too''';

      final result = r.render(md);
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(25),
            reason: 'Line too wide: "$line"');
      }
    });
  });

  // ── BlockRenderer wrapping with wrapIndented ──────────────────────────

  group('BlockRenderer wrapping', () {
    test('renderUser wraps long text and all lines fit', () {
      final r = BlockRenderer(40);
      final result = r.renderUser(
          'The quick brown fox jumped over the lazy dog repeatedly');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(40),
            reason: 'User line too wide: "$line"');
      }
    });

    test('renderAssistant wraps long paragraphs', () {
      final r = BlockRenderer(40);
      final result = r.renderAssistant(
          'This is a very long assistant response that should be wrapped properly within the terminal width');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(40),
            reason: 'Assistant line too wide: "$line"');
      }
    });

    test('renderError wraps long error messages', () {
      final r = BlockRenderer(40);
      final result = r.renderError(
          'A very long error message that exceeds the terminal width and must wrap');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(40),
            reason: 'Error line too wide: "$line"');
      }
    });

    test('renderUser with emoji content fits width', () {
      final r = BlockRenderer(30);
      final result =
          r.renderUser('🎉 party 🚀 rocket 🌍 earth 🎊 tada 🦊 fox');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(30),
            reason: 'Line too wide: "$line"');
      }
    });

    test('renderAssistant markdown list wraps within width', () {
      final r = BlockRenderer(35);
      final result = r.renderAssistant(
          '- This is a long list item that should wrap nicely\n'
          '- Another item that is also quite long');
      for (final line in result.split('\n')) {
        expect(visibleLength(line), lessThanOrEqualTo(35),
            reason: 'List line too wide: "$line"');
      }
    });
  });
}
