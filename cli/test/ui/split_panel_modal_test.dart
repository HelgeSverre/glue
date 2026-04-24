import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:test/test.dart';

void main() {
  group('SplitPanel', () {
    late SplitPanel panel;

    setUp(() {
      panel = SplitPanel(
        title: 'TEST',
        leftItems: ['item-a', 'item-b', 'item-c'],
        buildRightLines: (idx, width) => ['Detail for item $idx'],
      );
    });

    test('starts with selectedIndex 0', () {
      expect(panel.selectedIndex, 0);
    });

    test('is not complete initially', () {
      expect(panel.isComplete, false);
    });

    test('down arrow increments selection', () {
      panel.handleEvent(KeyEvent(Key.down));
      expect(panel.selectedIndex, 1);
    });

    test('up arrow decrements selection', () {
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.up));
      expect(panel.selectedIndex, 0);
    });

    test('up arrow does not go below 0', () {
      panel.handleEvent(KeyEvent(Key.up));
      expect(panel.selectedIndex, 0);
    });

    test('down arrow does not exceed item count', () {
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.down));
      expect(panel.selectedIndex, 2);
    });

    test('escape dismisses', () {
      panel.handleEvent(KeyEvent(Key.escape));
      expect(panel.isComplete, true);
    });

    test('enter selects current item', () async {
      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.enter));
      expect(panel.isComplete, true);
      final idx = await panel.selection;
      expect(idx, 1);
    });

    test('dismiss returns null selection', () async {
      panel.dismiss();
      final idx = await panel.selection;
      expect(idx, isNull);
    });

    test('render produces correct grid size', () {
      final bg = List.generate(24, (_) => ' ' * 80);
      final grid = panel.render(80, 24, bg);
      expect(grid.length, 24);
    });

    test('render includes panel title', () {
      final bg = List.generate(24, (_) => ' ' * 80);
      final grid = panel.render(80, 24, bg);
      final hasTitle = grid.any((line) => line.contains('TEST'));
      expect(hasTitle, true);
    });

    test('selection highlight is not broken by ANSI resets in items', () {
      final ansiPanel = SplitPanel(
        title: 'TEST',
        leftItems: [
          'skill-a  \x1b[32mproject\x1b[0m',
          'skill-b  \x1b[36mglobal\x1b[0m',
        ],
        buildRightLines: (idx, width) => ['Detail $idx'],
      );
      final bg = List.generate(24, (_) => ' ' * 80);
      final grid = ansiPanel.render(80, 24, bg);

      // Find the line containing the selected item (index 0).
      final selectedLine = grid.firstWhere(
        (line) => stripAnsi(line).contains('skill-a'),
      );

      // The reverse-video open (\x1b[7m) must appear before the item text
      // and must NOT be cancelled by an intermediate \x1b[0m before the
      // closing \x1b[27m.
      final afterOpen = selectedLine.indexOf('\x1b[7m');
      final closeTag = selectedLine.indexOf('\x1b[27m');
      expect(afterOpen, greaterThanOrEqualTo(0), reason: 'missing \\x1b[7m');
      expect(closeTag, greaterThan(afterOpen), reason: 'missing \\x1b[27m');

      // No bare \x1b[0m should appear between open and close.
      final between = selectedLine.substring(afterOpen, closeTag);
      expect(between.contains('\x1b[0m'), isFalse,
          reason: 'ANSI reset inside selection breaks reverse video');
    });

    test('barrier none keeps ANSI background on rows with overlay', () {
      final ansiPanel = SplitPanel(
        title: 'TEST',
        leftItems: ['item-a', 'item-b'],
        buildRightLines: (idx, width) => ['Detail $idx'],
        barrier: BarrierStyle.none,
      );
      final bg = List.generate(20, (_) => '\x1b[35m${'x' * 80}\x1b[0m');
      final grid = ansiPanel.render(80, 20, bg);
      final centerRow = grid[10];
      expect(centerRow, contains('\x1b[35m'));
      expect(visibleLength(centerRow), equals(80));
    });
  });
}
