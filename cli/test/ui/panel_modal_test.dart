import 'package:test/test.dart';

import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/panel_modal.dart';

void main() {
  group('PanelSize', () {
    group('PanelFixed', () {
      test('returns size when smaller than available', () {
        expect(PanelFixed(10).resolve(20), 10);
      });

      test('clamps to available when size exceeds it', () {
        expect(PanelFixed(30).resolve(20), 20);
      });

      test('returns available when equal', () {
        expect(PanelFixed(15).resolve(15), 15);
      });
    });

    group('PanelFluid', () {
      test('returns percentage of available', () {
        expect(PanelFluid(0.5, 5).resolve(100), 50);
      });

      test('floors fractional result', () {
        expect(PanelFluid(0.5, 5).resolve(33), 16);
      });

      test('uses minSize when percentage is smaller', () {
        expect(PanelFluid(0.1, 20).resolve(100), 20);
      });

      test('clamps to available when result exceeds it', () {
        expect(PanelFluid(0.9, 50).resolve(10), 10);
      });

      test('clamps minSize to available', () {
        expect(PanelFluid(0.1, 30).resolve(10), 10);
      });
    });
  });

  group('renderBorder', () {
    for (final style in PanelStyle.values) {
      group(style.name, () {
        test('produces correct number of lines', () {
          final lines = renderBorder(style, 30, 10, 'Test');
          expect(lines.length, 10);
        });

        test('each line has correct visible width', () {
          final lines = renderBorder(style, 30, 10, 'Test');
          for (var i = 0; i < lines.length; i++) {
            expect(visibleLength(lines[i]), 30,
                reason: 'line $i has wrong width');
          }
        });

        test('title appears in top border', () {
          final lines = renderBorder(style, 40, 5, 'MyTitle');
          expect(stripAnsi(lines.first), contains('MyTitle'));
        });
      });
    }

    group('simple', () {
      test('has correct corner characters', () {
        final lines = renderBorder(PanelStyle.simple, 20, 5, 'X');
        final top = stripAnsi(lines.first);
        final bottom = stripAnsi(lines.last);
        expect(top[0], '┌');
        expect(top[top.length - 1], '┐');
        expect(bottom[0], '└');
        expect(bottom[bottom.length - 1], '┘');
      });

      test('interior has border and padding', () {
        final lines = renderBorder(PanelStyle.simple, 20, 5, 'X');
        final interior = stripAnsi(lines[2]);
        expect(interior[0], '│');
        expect(interior[interior.length - 1], '│');
        expect(interior[1], ' ');
        expect(interior[interior.length - 2], ' ');
      });
    });

    group('heavy', () {
      test('has correct corner characters', () {
        final lines = renderBorder(PanelStyle.heavy, 20, 5, 'X');
        final top = stripAnsi(lines.first);
        final bottom = stripAnsi(lines.last);
        expect(top[0], '╔');
        expect(top[top.length - 1], '╗');
        expect(bottom[0], '╚');
        expect(bottom[bottom.length - 1], '╝');
      });

      test('interior has border and padding', () {
        final lines = renderBorder(PanelStyle.heavy, 20, 5, 'X');
        final interior = stripAnsi(lines[2]);
        expect(interior[0], '║');
        expect(interior[interior.length - 1], '║');
        expect(interior[1], ' ');
      });
    });

    group('tape', () {
      test('top line contains tape pattern', () {
        final lines = renderBorder(PanelStyle.tape, 30, 5, 'X');
        final top = stripAnsi(lines.first);
        expect(top, contains('▚'));
      });

      test('interior has border and padding', () {
        final lines = renderBorder(PanelStyle.tape, 20, 5, 'X');
        final interior = stripAnsi(lines[2]);
        expect(interior[0], '│');
        expect(interior[interior.length - 1], '│');
        expect(interior[1], ' ');
      });

      test('bottom line is tape pattern', () {
        final lines = renderBorder(PanelStyle.tape, 30, 5, 'X');
        final bottom = stripAnsi(lines.last);
        expect(bottom, contains('▚'));
        expect(bottom, contains('▞'));
      });
    });
  });

  group('applyBarrier', () {
    final testLines = [
      'Hello World',
      '\x1b[31mColored\x1b[0m text',
      'Third line',
    ];

    test('none returns lines unchanged', () {
      final result = applyBarrier(BarrierStyle.none, testLines);
      expect(result, same(testLines));
    });

    test('dim adds dim escape codes', () {
      final result = applyBarrier(BarrierStyle.dim, testLines);
      expect(result.length, testLines.length);
      for (final line in result) {
        expect(line, startsWith('\x1b[2m'));
        expect(line, endsWith('\x1b[0m'));
      }
    });

    test('dim strips original ANSI', () {
      final result = applyBarrier(BarrierStyle.dim, testLines);
      expect(result[1], contains('Colored text'));
      expect(result[1], isNot(contains('\x1b[31m')));
    });

    test('obscure replaces content with block characters', () {
      final result = applyBarrier(BarrierStyle.obscure, testLines);
      expect(result.length, testLines.length);
      for (var i = 0; i < result.length; i++) {
        final stripped = stripAnsi(result[i]);
        expect(stripped, isNot(contains(stripAnsi(testLines[i]))));
        expect(stripped, matches(RegExp(r'^░+$')));
      }
    });

    test('obscure preserves visible length', () {
      final result = applyBarrier(BarrierStyle.obscure, testLines);
      for (var i = 0; i < result.length; i++) {
        expect(visibleLength(result[i]), visibleLength(testLines[i]));
      }
    });

    test('preserves line count', () {
      for (final style in BarrierStyle.values) {
        final result = applyBarrier(style, testLines);
        expect(result.length, testLines.length,
            reason: '${style.name} changed line count');
      }
    });
  });
}
