import 'package:glue/glue.dart';
import 'package:test/test.dart';

void main() {
  late MarkdownRenderer renderer;

  setUp(() {
    renderer = MarkdownRenderer(80);
  });

  group('headings', () {
    test('h1 renders bold', () {
      final result = renderer.render('# Hello');
      expect(result, contains('\x1b[1m'));
      expect(result, contains('Hello'));
    });

    test('h2 renders bold', () {
      final result = renderer.render('## World');
      expect(result, contains('\x1b[1m'));
      expect(result, contains('World'));
    });

    test('h3 renders bold', () {
      final result = renderer.render('### Subtitle');
      expect(result, contains('\x1b[1m'));
      expect(result, contains('Subtitle'));
    });
  });

  group('inline styles', () {
    test('bold wraps with bold ANSI codes', () {
      final result = renderer.render('**bold**');
      expect(result, contains('\x1b[1m'));
      expect(result, contains('bold'));
      expect(result, contains('\x1b[22m'));
    });

    test('italic wraps with italic ANSI codes', () {
      final result = renderer.render('*italic*');
      expect(result, contains('\x1b[3m'));
      expect(result, contains('italic'));
      expect(result, contains('\x1b[23m'));
    });

    test('inline code wraps with color ANSI codes', () {
      final result = renderer.render('`code`');
      expect(result, contains('\x1b[33m'));
      expect(result, contains('code'));
      expect(result, contains('\x1b[39m'));
    });

    test('links render text with url in parens', () {
      final result = renderer.render('[click](https://example.com)');
      expect(result, contains('click'));
      expect(result, contains('(https://example.com)'));
    });
  });

  group('mixed inline', () {
    test('bold and italic in same line', () {
      final result = renderer.render('**bold** and *italic*');
      expect(result, contains('\x1b[1m'));
      expect(result, contains('\x1b[3m'));
      expect(result, contains('bold'));
      expect(result, contains('italic'));
    });
  });

  group('code blocks', () {
    test('fenced code block with language', () {
      final result = renderer.render('```dart\nprint("hi");\n```');
      expect(result, contains('dart'));
      expect(result, contains('print("hi");'));
      expect(result, contains('╭'));
      expect(result, contains('╰'));
      expect(result, contains('\x1b[2m'));
    });

    test('fenced code block without language', () {
      final result = renderer.render('```\nhello\n```');
      expect(result, contains('hello'));
      expect(result, contains('╭'));
      expect(result, contains('╰'));
    });
  });

  group('lists', () {
    test('unordered list with dash renders bullet', () {
      final result = renderer.render('- item one');
      expect(result, contains('• item one'));
    });

    test('unordered list with asterisk renders bullet', () {
      final result = renderer.render('* item two');
      expect(result, contains('• item two'));
    });

    test('ordered list preserves numbering', () {
      final result = renderer.render('1. first\n2. second');
      expect(result, contains('1. first'));
      expect(result, contains('2. second'));
    });
  });

  group('blockquotes', () {
    test('blockquote renders with vertical bar prefix', () {
      final result = renderer.render('> quoted text');
      expect(result, contains('│'));
      expect(result, contains('quoted text'));
      expect(result, contains('\x1b[90m'));
    });
  });

  group('empty lines', () {
    test('empty lines are preserved', () {
      final result = renderer.render('line one\n\nline two');
      final lines = result.split('\n');
      expect(lines.length, 3);
      expect(lines[1], '');
    });
  });

  group('unclosed code block', () {
    test('unclosed code block is rendered gracefully', () {
      final result = renderer.render('```\nsome code');
      expect(result, contains('some code'));
      expect(result, contains('╭'));
      expect(result, contains('╰'));
    });
  });

  group('nested markdown in lists', () {
    test('bold inside list item', () {
      final result = renderer.render('- **bold** item');
      expect(result, contains('•'));
      expect(result, contains('\x1b[1m'));
      expect(result, contains('bold'));
      expect(result, contains('item'));
    });
  });

  group('plain text', () {
    test('plain text passes through unchanged', () {
      final result = renderer.render('just some text');
      expect(result, 'just some text');
    });
  });

  group('tables', () {
    test('renders table with box-drawing characters', () {
      final result = renderer.render(
        '| Name | Age |\n'
        '|------|-----|\n'
        '| Alice | 30 |\n'
        '| Bob | 25 |',
      );
      final stripped = result.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      expect(stripped, contains('┌'));
      expect(stripped, contains('┐'));
      expect(stripped, contains('└'));
      expect(stripped, contains('┘'));
      expect(stripped, contains('│'));
      expect(stripped, contains('├'));
      expect(stripped, contains('┤'));
      expect(stripped, contains('Alice'));
      expect(stripped, contains('Bob'));
    });

    test('header row is bold', () {
      final result = renderer.render(
        '| Name | Age |\n'
        '|------|-----|\n'
        '| Alice | 30 |',
      );
      expect(result, contains('\x1b[1m'));
      expect(result, contains('Name'));
    });

    test('computes column widths from longest cell', () {
      final result = renderer.render(
        '| A | Longer |\n'
        '|---|--------|\n'
        '| Bigger | B |',
      );
      final stripped = result.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      final lines = stripped.split('\n');
      // All lines (top, header, separator, body, bottom) should be the same width
      final widths = lines.map((l) => l.trimRight().length).toSet();
      expect(widths.length, 1);
    });

    test('handles single column table', () {
      final result = renderer.render(
        '| Name |\n'
        '|------|\n'
        '| Alice |',
      );
      final stripped = result.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      expect(stripped, contains('Alice'));
      expect(stripped, contains('┌'));
      expect(stripped, contains('└'));
    });

    test('handles empty cells', () {
      final result = renderer.render(
        '| A | B |\n'
        '|---|---|\n'
        '| x |  |',
      );
      final stripped = result.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      expect(stripped, contains('x'));
    });

    test('table surrounded by other content', () {
      final result = renderer.render(
        'Before\n\n'
        '| Name | Age |\n'
        '|------|-----|\n'
        '| Alice | 30 |\n\n'
        'After',
      );
      final stripped = result.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      expect(stripped, contains('Before'));
      expect(stripped, contains('After'));
      expect(stripped, contains('Alice'));
      expect(stripped, contains('┌'));
    });

    test('inline formatting in table cells', () {
      final result = renderer.render(
        '| Name | Note |\n'
        '|------|------|\n'
        '| **Alice** | `code` |',
      );
      expect(result, contains('\x1b[1m'));
      expect(result, contains('Alice'));
      expect(result, contains('code'));
    });
  });
}
