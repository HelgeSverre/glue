import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:test/test.dart';

void main() {
  group('SelectPanel', () {
    test('enter selects current option', () async {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: const [
          SelectOption(value: 'alpha', label: 'alpha'),
          SelectOption(value: 'beta', label: 'beta'),
        ],
        searchEnabled: false,
      );

      panel.handleEvent(KeyEvent(Key.down));
      panel.handleEvent(KeyEvent(Key.enter));

      expect(await panel.selection, 'beta');
      expect(panel.isComplete, isTrue);
    });

    test('typing filters list and selects match', () async {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: const [
          SelectOption(value: 'alpha', label: 'alpha'),
          SelectOption(value: 'beta', label: 'beta'),
        ],
      );

      panel.render(80, 20, const []);
      panel.handleEvent(CharEvent('b'));
      panel.handleEvent(KeyEvent(Key.enter));

      expect(await panel.selection, 'beta');
    });

    test('enter with no match returns null', () async {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: const [
          SelectOption(value: 'alpha', label: 'alpha'),
        ],
      );

      panel.render(80, 20, const []);
      panel.handleEvent(CharEvent('z'));
      panel.handleEvent(KeyEvent(Key.enter));

      expect(await panel.selection, isNull);
      expect(panel.isComplete, isTrue);
    });

    test('render returns terminal-height grid', () {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: const [SelectOption(value: 'alpha', label: 'alpha')],
        headerLines: const ['HEADER'],
        barrier: BarrierStyle.none,
      );

      final lines = panel.render(100, 24, const []);
      expect(lines, hasLength(24));
    });

    test('barrier none keeps ANSI background on rows with overlay', () {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: const [SelectOption(value: 'alpha', label: 'alpha')],
        searchEnabled: false,
        barrier: BarrierStyle.none,
      );
      final bg = List.generate(18, (_) => '\x1b[36m${'x' * 80}\x1b[0m');
      final lines = panel.render(80, 18, bg);
      final centerRow = lines[9];
      expect(centerRow, contains('\x1b[36m'));
      expect(visibleLength(centerRow), equals(80));
    });
  });
}
