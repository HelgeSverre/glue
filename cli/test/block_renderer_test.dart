import 'dart:io';

import 'package:glue/glue.dart';
import 'package:test/test.dart';

/// Strip ANSI escape sequences for measuring visible width.
String stripAnsi(String s) => s
    .replaceAll(RegExp(r'\x1b\][^\x07]*\x07'), '')
    .replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

void main() {
  late BlockRenderer renderer;

  setUp(() {
    renderer = BlockRenderer(80);
  });

  group('renderUser', () {
    test('contains "You" header and user text', () {
      final output = renderer.renderUser('Hello world');
      expect(output, contains('You'));
      expect(output, contains('Hello world'));
    });

    test('indents the body text', () {
      final output = renderer.renderUser('Hello');
      final lines = output.split('\n');
      // Body lines should start with two spaces
      for (final line in lines.skip(1)) {
        expect(stripAnsi(line), startsWith('  '));
      }
    });

    test('handles empty text', () {
      final output = renderer.renderUser('');
      expect(output, contains('You'));
    });
  });

  group('renderAssistant', () {
    test('contains "Glue" header and text', () {
      final output = renderer.renderAssistant('Hello from assistant');
      expect(output, contains('Glue'));
      expect(output, contains('Hello from assistant'));
    });

    test('renderThinking: dim+italic body with ▸ Thinking header', () {
      final output = renderer.renderThinking('considering options');
      expect(output, contains('▸ Thinking'));
      // ANSI: \x1b[2m = dim, \x1b[3m = italic
      expect(output, contains('\x1b[2m'));
      expect(output, contains('\x1b[3m'));
      expect(output, contains('considering options'));
    });

    test('renders bold markdown', () {
      final output = renderer.renderAssistant('This is **bold** text');
      // Bold ANSI: \x1b[1m
      expect(output, contains('\x1b[1m'));
      expect(output, contains('bold'));
    });

    test('renders inline code markdown', () {
      final output = renderer.renderAssistant('Use `dart test` here');
      expect(output, contains('dart test'));
      // Inline code gets yellow: \x1b[33m
      expect(output, contains('\x1b[33m'));
    });

    test('handles empty text', () {
      final output = renderer.renderAssistant('');
      expect(output, contains('Glue'));
    });
  });

  group('renderToolCall', () {
    test('contains tool name in header', () {
      final output = renderer.renderToolCall('readFile', null);
      expect(output, contains('Tool: readFile'));
    });

    test('shows args when provided', () {
      final output = renderer.renderToolCall('readFile', {
        'path': '/tmp/test.txt',
        'encoding': 'utf8',
      });
      expect(output, contains('path'));
      expect(output, contains('/tmp/test.txt'));
      expect(output, contains('encoding'));
    });

    test('only shows header with null args', () {
      final output = renderer.renderToolCall('listFiles', null);
      expect(output.split('\n'), hasLength(1));
    });

    test('only shows header with empty args', () {
      final output = renderer.renderToolCall('listFiles', {});
      expect(output.split('\n'), hasLength(1));
    });

    test('handles empty text for name', () {
      final output = renderer.renderToolCall('', null);
      expect(output, contains('Tool:'));
    });
  });

  group('renderToolResult', () {
    test('shows ✓ for success', () {
      final output = renderer.renderToolResult('Done', success: true);
      expect(output, contains('✓'));
    });

    test('shows ✗ for failure', () {
      final output = renderer.renderToolResult('Failed', success: false);
      expect(output, contains('✗'));
    });

    test('includes content', () {
      final output = renderer.renderToolResult('file contents here');
      expect(output, contains('file contents here'));
    });

    test('handles empty content', () {
      final output = renderer.renderToolResult('');
      expect(output, contains('✓'));
    });

    test('truncates content beyond 20 lines', () {
      final longContent = List.generate(30, (i) => 'line $i').join('\n');
      final output = renderer.renderToolResult(longContent);
      expect(output, contains('more lines'));
    });

    test('preserves content at exactly 20 lines', () {
      final content = List.generate(20, (i) => 'line $i').join('\n');
      final output = renderer.renderToolResult(content);
      expect(output, isNot(contains('more lines')));
    });
  });

  group('renderError', () {
    test('contains "Error" header and message', () {
      final output = renderer.renderError('Something broke');
      expect(output, contains('Error'));
      expect(output, contains('Something broke'));
    });

    test('uses red ANSI color', () {
      final output = renderer.renderError('fail');
      // Red: \x1b[31m
      expect(output, contains('\x1b[31m'));
    });

    test('handles empty message', () {
      final output = renderer.renderError('');
      expect(output, contains('Error'));
    });
  });

  group('renderSystem', () {
    test('wraps text in gray ANSI', () {
      final output = renderer.renderSystem('System info');
      expect(output, contains('\x1b[90m'));
      expect(output, contains('System info'));
      expect(output, endsWith('\x1b[39m'));
    });

    test('handles empty text', () {
      final output = renderer.renderSystem('');
      expect(output, equals(' \x1b[90m\x1b[39m'));
    });

    test('wraps bare URLs in OSC 8 hyperlinks', () {
      final output = renderer.renderSystem('See https://example.com/docs.');
      expect(output, contains('\x1b]8;;https://example.com/docs\x07'));
      expect(output, contains('https://example.com/docs'));
    });
  });

  group('word wrapping', () {
    test('renderUser wraps long text at width boundary', () {
      final r = BlockRenderer(40);
      final longText = 'word ' * 30; // 150 chars
      final output = r.renderUser(longText.trim());
      final lines = output.split('\n');
      for (final line in lines) {
        // Visible width should not exceed 40
        expect(stripAnsi(line).length, lessThanOrEqualTo(40));
      }
    });

    test('renderError wraps long text', () {
      final r = BlockRenderer(40);
      final longText = 'error ' * 30;
      final output = r.renderError(longText.trim());
      final lines = output.split('\n');
      for (final line in lines.skip(1)) {
        expect(stripAnsi(line).length, lessThanOrEqualTo(40));
      }
    });
  });

  group('truncation', () {
    test('tool result truncates with "more lines" indicator', () {
      final content = List.generate(50, (i) => 'Result line $i').join('\n');
      final output = renderer.renderToolResult(content);
      final stripped = stripAnsi(output);
      expect(stripped, contains('30 more lines'));
    });
  });

  group('width respect', () {
    test('renderUser output lines do not exceed width', () {
      final r = BlockRenderer(60);
      final text = 'The quick brown fox jumps over the lazy dog. ' * 10;
      final output = r.renderUser(text.trim());
      for (final line in output.split('\n')) {
        expect(stripAnsi(line).length, lessThanOrEqualTo(60));
      }
    });

    test('renderToolResult output lines do not exceed width', () {
      final r = BlockRenderer(50);
      final content = 'x' * 200;
      final output = r.renderToolResult(content);
      for (final line in output.split('\n')) {
        expect(stripAnsi(line).length, lessThanOrEqualTo(50));
      }
    });
  });

  group('renderToolCall file path links', () {
    test('tool call with path arg wraps in OSC 8 file:// link', () {
      final result = renderer.renderToolCall('read_file', {
        'path': '/src/main.dart',
      });
      // Compute the expected link via the same helper: on Windows
      // `/src/main.dart` is not absolute, so the file URI differs from a
      // hardcoded POSIX one.
      expect(result, contains(osc8FileLink('/src/main.dart')));
      expect(result, contains('/src/main.dart'));
      expect(result, contains('\x1b]8;;\x07'));
    });

    test('tool call with relative path arg wraps in OSC 8 link', () {
      final result = renderer.renderToolCall('read_file', {
        'path': 'lib/foo.dart',
      });
      expect(result, contains(osc8FileLink('lib/foo.dart')));
    });

    test('tool call with url arg wraps in OSC 8 link', () {
      final result = renderer.renderToolCall('web_fetch', {
        'url': 'https://example.com/docs',
      });
      expect(result, contains('\x1b]8;;https://example.com/docs\x07'));
    });

    test('tool call without path arg renders normally', () {
      final result = renderer.renderToolCall('bash', {'command': 'ls -la'});
      expect(result, isNot(contains('\x1b]8;;file://')));
    });

    test('tool call with null args renders header only', () {
      final result = renderer.renderToolCall('bash', null);
      expect(result, contains('Tool: bash'));
      expect(result, isNot(contains('\x1b]8;;')));
    });
  });

  group('renderToolResult grep output links', () {
    test('grep-style file:line output gets file path linked', () {
      final result = renderer.renderToolResult(
        'src/main.dart:42:  print("hello");',
      );
      expect(
        result,
        contains('\x1b]8;;${File('src/main.dart').absolute.uri}\x07'),
      );
      expect(result, contains('src/main.dart'));
    });

    test('multiple grep lines each get linked', () {
      final result = renderer.renderToolResult('a.dart:1: foo\nb.dart:2: bar');
      expect(result, contains('\x1b]8;;${File('a.dart').absolute.uri}\x07'));
      expect(result, contains('\x1b]8;;${File('b.dart').absolute.uri}\x07'));
    });

    test('non-grep lines are not linked', () {
      final result = renderer.renderToolResult('No matches found.');
      expect(result, isNot(contains('\x1b]8;;file://')));
    });

    test('bare URLs in tool results are linked', () {
      final result = renderer.renderToolResult(
        'Published gist: https://gist.github.com/x/y',
      );
      expect(result, contains('\x1b]8;;https://gist.github.com/x/y\x07'));
    });
  });

  group('renderBash', () {
    test('renders fieldset box with command in legend', () {
      final output = renderer.renderBash('git push', 'Everything up-to-date');
      final stripped = stripAnsi(output);
      expect(stripped, contains('git push'));
      expect(stripped, contains('Everything up-to-date'));
    });

    test('renders top border with command legend', () {
      final output = renderer.renderBash('ls', 'file.txt');
      final stripped = stripAnsi(output);
      final lines = stripped.split('\n');
      expect(lines.first, contains('┌'));
      expect(lines.first, contains('ls'));
      expect(lines.first, contains('┐'));
    });

    test('renders bottom border', () {
      final output = renderer.renderBash('ls', 'file.txt');
      final stripped = stripAnsi(output);
      final lines = stripped.split('\n');
      expect(lines.last, contains('└'));
      expect(lines.last, contains('┘'));
    });

    test('renders side borders on content lines', () {
      final output = renderer.renderBash('ls', 'file.txt');
      final stripped = stripAnsi(output);
      final contentLines = stripped
          .split('\n')
          .where((l) => l.contains('file.txt'))
          .toList();
      expect(contentLines, isNotEmpty);
      for (final line in contentLines) {
        expect(line, contains('│'));
      }
    });

    test('handles empty output', () {
      final output = renderer.renderBash('true', '');
      final stripped = stripAnsi(output);
      expect(stripped, contains('true'));
      expect(stripped, contains('┌'));
      expect(stripped, contains('└'));
    });

    test('handles multi-line output', () {
      final output = renderer.renderBash('ls', 'a.txt\nb.txt\nc.txt');
      final stripped = stripAnsi(output);
      expect(stripped, contains('a.txt'));
      expect(stripped, contains('b.txt'));
      expect(stripped, contains('c.txt'));
    });

    test('truncates long output with notice', () {
      final longOutput = List.generate(60, (i) => 'line $i').join('\n');
      final output = renderer.renderBash('cmd', longOutput, maxLines: 50);
      final stripped = stripAnsi(output);
      expect(stripped, contains('lines above'));
      expect(stripped, contains('line 59'));
      expect(stripped, isNot(contains('line 0\n')));
    });

    test('content lines do not exceed terminal width', () {
      final r = BlockRenderer(40);
      final longLine = 'x' * 100;
      final output = r.renderBash('cmd', longLine);
      for (final line in output.split('\n')) {
        expect(stripAnsi(line).length, lessThanOrEqualTo(40));
      }
    });
  });

  // C3: untrusted model/tool text must never carry raw control bytes into the
  // terminal. A poisoned file, web page, or MCP tool result could otherwise
  // emit OSC 52 (clipboard write), OSC 8 (arbitrary hyperlink), or CSI
  // sequences (screen clear, cursor moves, device queries that answer onto
  // stdin as if they were keystrokes).
  group('C3: ANSI escape injection is neutralized', () {
    // OSC 52 clipboard write with a base64 payload, terminated by BEL.
    const osc52 = '\x1b]52;c;aGFjaw==\x07';
    // CSI erase-display ("clear screen").
    const clearScreen = '\x1b[2J';
    // Device Status Report — some terminals answer onto stdin.
    const deviceQuery = '\x1b[6n';

    test('renderAssistant strips OSC 52 clipboard sequence', () {
      final output = renderer.renderAssistant('hi $osc52 there');
      expect(output, isNot(contains('\x1b]52')));
      expect(output, isNot(contains('\x07')));
    });

    test('renderAssistant strips CSI clear-screen and device-query', () {
      final output = renderer.renderAssistant(
        'a ${clearScreen}b ${deviceQuery}c',
      );
      expect(output, isNot(contains('\x1b[2J')));
      expect(output, isNot(contains('\x1b[6n')));
      // Visible text survives (minus the escape introducer).
      expect(stripAnsi(output), contains('c'));
    });

    test('renderThinking strips injected control sequences', () {
      final output = renderer.renderThinking('think $osc52$clearScreen');
      expect(output, isNot(contains('\x1b]52')));
      expect(output, isNot(contains('\x1b[2J')));
      expect(output, isNot(contains('\x07')));
    });

    test('renderToolResult strips injected control sequences', () {
      final output = renderer.renderToolResult('tool $osc52$clearScreen out');
      expect(output, isNot(contains('\x1b]52')));
      expect(output, isNot(contains('\x1b[2J')));
      expect(output, isNot(contains('\x07')));
      expect(stripAnsi(output), contains('out'));
    });

    test('renderToolResult strips C1 control bytes and DEL', () {
      // 0x9b is the C1 CSI introducer; 0x7f is DEL; a bare ESC (0x1b) too.
      final output = renderer.renderToolResult('x\x9b2J\x7f\x1byz');
      expect(output, isNot(contains('\x9b')));
      expect(output, isNot(contains('\x7f')));
      expect(stripAnsi(output), contains('x'));
      expect(stripAnsi(output), contains('yz'));
    });

    test('markdown link with escape-laden target does not emit raw OSC 8', () {
      // The link URL is attacker-controlled; a raw BEL inside it must be
      // stripped before it reaches the OSC 8 envelope, so it can neither
      // prematurely terminate the sequence nor inject a second one. The BEL
      // bytes the renderer emits as legitimate OSC 8 terminators are fine.
      final output = renderer.renderAssistant('[click](http://x\x07evil)');
      expect(output, isNot(contains('x\x07evil')));
      expect(output, contains('http://xevil'));
    });

    test('preserves newlines and tabs in untrusted text', () {
      final output = renderer.renderAssistant('line1\nline2\twith tab');
      final stripped = stripAnsi(output);
      expect(stripped, contains('line1'));
      expect(stripped, contains('line2'));
    });
  });
}
