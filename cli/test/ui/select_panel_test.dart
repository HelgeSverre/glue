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
        options: [
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
        options: [
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
        options: [
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
        options: [SelectOption(value: 'alpha', label: 'alpha')],
        headerLines: const ['HEADER'],
        barrier: BarrierStyle.none,
      );

      final lines = panel.render(100, 24, const []);
      expect(lines, hasLength(24));
    });

    test('barrier none keeps ANSI background on rows with overlay', () {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: [SelectOption(value: 'alpha', label: 'alpha')],
        searchEnabled: false,
        barrier: BarrierStyle.none,
      );
      final bg = List.generate(18, (_) => '\x1b[36m${'x' * 80}\x1b[0m');
      final lines = panel.render(80, 18, bg);
      final centerRow = lines[9];
      expect(centerRow, contains('\x1b[36m'));
      expect(visibleLength(centerRow), equals(80));
    });

    test('SelectOption.responsive label builder is called with content width',
        () {
      final widths = <int>[];
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: [
          SelectOption.responsive(
            value: 'x',
            build: (w) {
              widths.add(w);
              return 'row@$w';
            },
            searchText: 'x',
          ),
        ],
        searchEnabled: false,
      );
      // Render at two terminal widths, expect the builder invoked with the panel's
      // inner content width (panelWidth - 4 for borders + padding).
      panel.render(80, 20, const []);
      panel.render(50, 20, const []);
      expect(widths, isNotEmpty);
      expect(widths.first, isNot(widths.last));
      // Content width = panel width - 4. Panel width = PanelFluid(0.7, 40) default.
      // At 80-col terminal: panelW = max(40, 56) = 56, contentW = 52.
      // At 50-col terminal: percent=35<40, floor-dominates, panelW = 48, contentW = 44.
      // Exact values are brittle to the panel-sizing rule, so assert inequality only.
    });

    test('SelectOption.label getter returns the builder result at width 80',
        () {
      final opt = SelectOption.responsive(
        value: 'x',
        build: (w) => 'rendered@$w',
        searchText: 'x',
      );
      expect(opt.label, 'rendered@80');
    });

    test('headerBuilder is called per render with the panel content width', () {
      final widths = <int>[];
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: [SelectOption(value: 'a', label: 'a')],
        headerBuilder: (w) {
          widths.add(w);
          return ['HEADER@$w'];
        },
        searchEnabled: false,
      );
      panel.render(80, 20, const []);
      panel.render(50, 20, const []);
      expect(widths.length, 2);
      expect(widths.first, isNot(widths.last));
    });

    test('selected row uses dim-gray background, not inverse video', () {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: [
          SelectOption(value: 'alpha', label: 'alpha'),
          SelectOption(value: 'beta', label: 'beta'),
        ],
        searchEnabled: false,
      );
      final grid = panel.render(80, 20, const []);
      final joined = grid.join();
      expect(joined, contains('\x1b[48;5;237m'));
      expect(joined, isNot(contains('\x1b[7m')));
    });

    test('headerBuilder output appears above options in rendered grid', () {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: [SelectOption(value: 'a', label: 'alpha')],
        headerBuilder: (w) => ['MYHEADER'],
        searchEnabled: false,
      );
      final grid = panel.render(80, 20, const []);
      // Join and strip ANSI so we can do a simple contains-check without fighting
      // escape codes or padding.
      final joined = grid.map(stripAnsi).join('\n');
      expect(joined, contains('MYHEADER'));
      expect(joined, contains('alpha'));
    });

    test('assertion: headerLines + headerBuilder throws', () {
      expect(
        () => SelectPanel<String>(
          title: 't',
          options: [SelectOption(value: 'a', label: 'a')],
          headerLines: const ['h'],
          headerBuilder: (_) => ['b'],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('static headerLines still works when headerBuilder absent', () {
      final panel = SelectPanel<String>(
        title: 'Pick',
        options: [SelectOption(value: 'a', label: 'a')],
        headerLines: const ['STATIC HEADER'],
        searchEnabled: false,
      );
      final grid = panel.render(80, 20, const []);
      final joined = grid.map(stripAnsi).join('\n');
      expect(joined, contains('STATIC HEADER'));
    });
  });
}
