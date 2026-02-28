import 'package:test/test.dart';

import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/split_panel_modal.dart';

void main() {
  group('SplitPanelModal', () {
    late SplitPanelModal panel;

    setUp(() {
      panel = SplitPanelModal(
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
  });
}
