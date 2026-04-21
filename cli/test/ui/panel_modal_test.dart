import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/box.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:test/test.dart';

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

    group('PanelFluid small-terminal fallback', () {
      test('expands to available-margin when floor dominates', () {
        final size = PanelFluid(0.7, 40);
        // 42 * 0.7 = 29 < 40 → floor hit. available - margin = 40, 40 >= min.
        expect(size.resolve(42), 40);
        // 43 * 0.7 = 30 < 40 → floor hit. available - margin = 41, 41 >= min.
        expect(size.resolve(43), 41);
        // 45 * 0.7 = 31 < 40 → floor hit. available - margin = 43.
        expect(size.resolve(45), 43);
        // 50 * 0.7 = 35 < 40 → floor hit. available - margin = 48.
        expect(size.resolve(50), 48);
      });

      test('uses percent when terminal is comfortably above floor', () {
        final size = PanelFluid(0.7, 40);
        // 60 * 0.7 = 42 >= 40 → percent path.
        expect(size.resolve(60), 42);
        // 80 * 0.7 = 56 >= 40.
        expect(size.resolve(80), 56);
        // 120 * 0.7 = 84.
        expect(size.resolve(120), 84);
      });

      test('falls back to available on very tiny terminals', () {
        // available 10, min 50 → percent 9 < min, but available - margin = 8 < min,
        // so clamp to available (10). Matches the pre-existing
        // "clamps to available when result exceeds it" test.
        expect(PanelFluid(0.9, 50).resolve(10), 10);
      });

      test('margin is configurable', () {
        final size = PanelFluid(0.7, 40, margin: 4);
        // available 50, percent 35 < 40 → floor hit. available - margin = 46.
        expect(size.resolve(50), 46);
      });

      test('returns 0 on non-positive available', () {
        expect(PanelFluid(0.7, 40).resolve(0), 0);
        expect(PanelFluid(0.7, 40).resolve(-5), 0);
      });
    });
  });

  group('Box.renderFrame', () {
    for (final entry in {
      'light': Box.light,
      'heavy': Box.heavy,
      'rounded': Box.rounded,
    }.entries) {
      group(entry.key, () {
        test('produces correct number of lines', () {
          final lines = entry.value.renderFrame(30, 10, 'Test');
          expect(lines.length, 10);
        });

        test('each line has correct visible width', () {
          final lines = entry.value.renderFrame(30, 10, 'Test');
          for (var i = 0; i < lines.length; i++) {
            expect(visibleLength(lines[i]), 30,
                reason: 'line $i has wrong width');
          }
        });

        test('title appears in top border', () {
          final lines = entry.value.renderFrame(40, 5, 'MyTitle');
          expect(stripAnsi(lines.first), contains('MyTitle'));
        });
      });
    }

    group('light', () {
      test('has correct corner characters', () {
        final lines = Box.light.renderFrame(20, 5, 'X');
        final top = stripAnsi(lines.first);
        final bottom = stripAnsi(lines.last);
        expect(top[0], '┌');
        expect(top[top.length - 1], '┐');
        expect(bottom[0], '└');
        expect(bottom[bottom.length - 1], '┘');
      });

      test('interior has border and padding', () {
        final lines = Box.light.renderFrame(20, 5, 'X');
        final interior = stripAnsi(lines[2]);
        expect(interior[0], '│');
        expect(interior[interior.length - 1], '│');
        expect(interior[1], ' ');
        expect(interior[interior.length - 2], ' ');
      });
    });

    group('heavy', () {
      test('has correct corner characters', () {
        final lines = Box.heavy.renderFrame(20, 5, 'X', color: '\x1b[33m');
        final top = stripAnsi(lines.first);
        final bottom = stripAnsi(lines.last);
        expect(top[0], '╔');
        expect(top[top.length - 1], '╗');
        expect(bottom[0], '╚');
        expect(bottom[bottom.length - 1], '╝');
      });

      test('interior has border and padding', () {
        final lines = Box.heavy.renderFrame(20, 5, 'X', color: '\x1b[33m');
        final interior = stripAnsi(lines[2]);
        expect(interior[0], '║');
        expect(interior[interior.length - 1], '║');
        expect(interior[1], ' ');
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
        expect(line, endsWith('\x1b[22m'));
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

  group('PanelModal', () {
    late PanelModal panel;

    setUp(() {
      panel = PanelModal(
        title: 'TEST',
        lines: List.generate(30, (i) => 'Line $i'),
        barrier: BarrierStyle.dim,
        width: PanelFixed(40),
        height: PanelFixed(10),
      );
    });

    test('initial scroll offset is 0', () {
      expect(panel.scrollOffset, 0);
    });

    test('scroll down advances offset', () {
      panel.handleEvent(KeyEvent(Key.down));
      expect(panel.scrollOffset, 1);
    });

    test('scroll up at top stays at 0', () {
      panel.handleEvent(KeyEvent(Key.up));
      expect(panel.scrollOffset, 0);
    });

    test('scroll clamps to max', () {
      for (var i = 0; i < 50; i++) {
        panel.handleEvent(KeyEvent(Key.down));
      }
      // 30 lines, 8 visible (10 - 2 borders), max scroll = 22
      expect(panel.scrollOffset, 22);
    });

    test('page down scrolls by visible height', () {
      panel.handleEvent(KeyEvent(Key.pageDown));
      // visible height = 10 - 2 = 8
      expect(panel.scrollOffset, 8);
    });

    test('escape completes result when dismissable', () {
      expect(panel.isComplete, false);
      panel.handleEvent(KeyEvent(Key.escape));
      expect(panel.isComplete, true);
    });

    test('escape does not complete when not dismissable', () {
      final locked = PanelModal(
        title: 'LOCKED',
        lines: ['content'],
        barrier: BarrierStyle.dim,
        dismissable: false,
      );
      locked.handleEvent(KeyEvent(Key.escape));
      expect(locked.isComplete, false);
    });

    test('swallows all other input', () {
      expect(panel.handleEvent(CharEvent('a')), true);
    });

    test('triggers editor callback via e key', () async {
      var opened = 0;
      final view = PanelModal(
        title: 'VIEW',
        lines: const ['one'],
        onOpenInEditor: () async {
          opened++;
        },
      );

      view.handleEvent(CharEvent('e'));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(opened, 1);
    });

    test('triggers editor callback via Ctrl+E', () async {
      var opened = 0;
      final view = PanelModal(
        title: 'VIEW',
        lines: const ['one'],
        onOpenInEditor: () async {
          opened++;
        },
      );

      view.handleEvent(KeyEvent(Key.ctrlE));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(opened, 1);
    });

    test('returns false when already complete', () {
      panel.dismiss();
      expect(panel.handleEvent(KeyEvent(Key.down)), false);
    });

    test('dismiss completes the result future', () {
      panel.dismiss();
      expect(panel.isComplete, true);
    });

    test('render produces correct number of lines', () {
      final bg = List.generate(24, (i) => 'bg $i');
      final rendered = panel.render(80, 24, bg);
      expect(rendered.length, 24);
    });

    test('render shows panel content in output', () {
      final bg = List.generate(24, (i) => '');
      final rendered = panel.render(80, 24, bg);
      final allText = rendered.map(stripAnsi).join('\n');
      expect(allText, contains('Line 0'));
      expect(allText, contains('TEST'));
    });

    test('render applies barrier to background', () {
      final bg = List.generate(24, (i) => 'visible background $i');
      final rendered = panel.render(80, 24, bg);
      final firstLine = rendered.first;
      expect(firstLine, contains('\x1b[2m'));
    });

    test('render with barrier none preserves ANSI background outside panel',
        () {
      final noBarrier = PanelModal(
        title: 'TEST',
        lines: const ['x'],
        barrier: BarrierStyle.none,
        width: PanelFixed(20),
        height: PanelFixed(6),
      );
      final bg = List.generate(12, (_) => '\x1b[31m${'x' * 40}\x1b[0m');
      final rendered = noBarrier.render(40, 12, bg);
      final centerRow = rendered[5];
      expect(centerRow, contains('\x1b[31m'));
    });
  });

  group('PanelModal selectable', () {
    late PanelModal panel;

    setUp(() {
      panel = PanelModal(
        title: 'SELECT',
        lines: List.generate(20, (i) => 'Item $i'),
        barrier: BarrierStyle.dim,
        width: PanelFixed(40),
        height: PanelFixed(10),
        selectable: true,
      );
    });

    test('initial selectedIndex is 0', () {
      expect(panel.selectedIndex, 0);
    });

    test('down moves selection forward', () {
      panel.handleEvent(KeyEvent(Key.down));
      expect(panel.selectedIndex, 1);
    });

    test('up at top stays at 0', () {
      panel.handleEvent(KeyEvent(Key.up));
      expect(panel.selectedIndex, 0);
    });

    test('selection clamps to last item', () {
      for (var i = 0; i < 50; i++) {
        panel.handleEvent(KeyEvent(Key.down));
      }
      expect(panel.selectedIndex, 19);
    });

    test('enter completes selection with index', () async {
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.enter));
      expect(panel.isComplete, true);
      expect(await panel.selection, 2);
    });

    test('escape completes selection with null', () async {
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.escape));
      expect(panel.isComplete, true);
      expect(await panel.selection, null);
    });

    test('selection auto-scrolls when moving past visible area', () {
      // visible height = 10 - 2 = 8
      for (var i = 0; i < 9; i++) {
        panel.handleEvent(KeyEvent(Key.down));
      }
      expect(panel.selectedIndex, 9);
      expect(panel.scrollOffset, greaterThan(0));
    });

    test('render highlights selected row with a dim-gray background', () {
      final bg = List.generate(24, (i) => '');
      final rendered = panel.render(80, 24, bg);
      final allText = rendered.join();
      expect(allText, contains('\x1b[48;5;237m'));
      expect(allText, isNot(contains('\x1b[7m')));
    });

    test('non-selectable panel has no selection future', () async {
      final plain = PanelModal(
        title: 'PLAIN',
        lines: ['a', 'b'],
        barrier: BarrierStyle.dim,
      );
      expect(await plain.selection, null);
    });

    test('selectedIndex is -1 for non-selectable panel', () {
      final plain = PanelModal(
        title: 'PLAIN',
        lines: ['a', 'b'],
        barrier: BarrierStyle.dim,
      );
      expect(plain.selectedIndex, -1);
    });
  });

  group('PanelModal.responsive', () {
    test('linesBuilder is called per render with content width', () {
      final widths = <int>[];
      final panel = PanelModal.responsive(
        title: 'HELP',
        linesBuilder: (w) {
          widths.add(w);
          return ['line@$w'];
        },
      );
      // Discard the pre-warm call made by the constructor; assert only
      // against the per-render calls.
      widths.clear();
      panel.render(80, 20, const []);
      panel.render(60, 20, const []);
      expect(widths.length, 2);
      expect(widths.first, isNot(widths.last));
    });

    test('rendered output reflects builder result at current width', () {
      final panel = PanelModal.responsive(
        title: 'HELP',
        linesBuilder: (w) => ['WIDTH=$w'],
      );
      final grid = panel.render(80, 20, const []);
      final joined = grid.map(stripAnsi).join('\n');
      expect(joined, contains('WIDTH='));
    });

    test('static PanelModal still renders provided lines', () {
      final panel = PanelModal(
        title: 'HELP',
        lines: const ['STATIC'],
      );
      final grid = panel.render(80, 20, const []);
      final joined = grid.map(stripAnsi).join('\n');
      expect(joined, contains('STATIC'));
    });

    test('handleEvent after render uses cached last lines for bounds', () {
      final panel = PanelModal.responsive(
        title: 'HELP',
        linesBuilder: (_) => List.generate(50, (i) => 'line$i'),
        selectable: true,
      );
      panel.render(80, 20, const []);
      // Scroll way down; cached length 50 should allow movement.
      for (var i = 0; i < 60; i++) {
        panel.handleEvent(KeyEvent(Key.down));
      }
      // No exception, no infinite range — just verifies the cached path works.
      expect(panel.selectedIndex, greaterThan(0));
    });

    test('selectable .responsive navigates correctly before first render', () {
      final panel = PanelModal.responsive(
        title: 'HELP',
        linesBuilder: (_) => List.generate(10, (i) => 'row$i'),
        selectable: true,
      );
      // Intentionally press Down BEFORE any render() call.
      panel.handleEvent(KeyEvent(Key.down));
      expect(panel.selectedIndex, greaterThanOrEqualTo(0));
      expect(panel.selectedIndex, lessThan(10));
    });
  });
}
