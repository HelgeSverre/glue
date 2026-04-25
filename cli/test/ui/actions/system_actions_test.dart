import 'package:glue/src/ui/rendering/ansi_utils.dart';
import 'package:glue/src/ui/actions/system_actions.dart';
import 'package:glue/src/ui/components/panel.dart';
import 'package:glue/src/ui/services/panels.dart';
import 'package:test/test.dart';

void main() {
  group('buildHelpLines', () {
    test('help lines key column scales with width', () {
      final wide = buildHelpLines(const [], 120);
      final narrow = buildHelpLines(const [], 36);

      String pickLine(List<String> ls, String keyName) =>
          ls.firstWhere((l) => stripAnsi(l).contains(keyName));

      final wideLine = stripAnsi(pickLine(wide, 'Ctrl+U'));
      final narrowLine = stripAnsi(pickLine(narrow, 'Ctrl+U'));

      final wideRight = wideLine.substring(2);
      final narrowRight = narrowLine.substring(2);

      int descOffset(String line) {
        var i = 'Ctrl+U'.length;
        while (i < line.length && line[i] == ' ') {
          i++;
        }
        return i;
      }

      expect(descOffset(wideRight), greaterThan(descOffset(narrowRight)));
    });

    test('help lines include all section headers', () {
      final lines = buildHelpLines(const [], 80);
      final joined = lines.map(stripAnsi).join('\n');
      expect(joined, contains('COMMANDS'));
      expect(joined, contains('KEYBINDINGS'));
      expect(joined, contains('PERMISSIONS'));
      expect(joined, contains('FILE REFERENCES'));
    });
  });

  group('Panels', () {
    test('push and remove mutate the underlying stack and trigger a render',
        () {
      final stack = <AbstractPanel>[];
      var renders = 0;
      final panels = Panels(stack: stack, render: () => renders++);

      final panel = Panel(
        title: 't',
        lines: const ['x'],
        dismissable: false,
      );

      panels.push(panel);
      expect(stack, [panel]);
      expect(renders, 1);

      panels.remove(panel);
      expect(stack, isEmpty);
      expect(renders, 2);
    });

    test('remove is a no-op when the panel is not present', () {
      final stack = <AbstractPanel>[];
      var renders = 0;
      final panels = Panels(stack: stack, render: () => renders++);

      final panel = Panel(
        title: 't',
        lines: const ['x'],
        dismissable: false,
      );
      panels.remove(panel);

      expect(stack, isEmpty);
      // A render is still scheduled so any stale barrier redraws cleanly.
      expect(renders, 1);
    });

    test('push preserves stack order for nested panels', () {
      final stack = <AbstractPanel>[];
      final panels = Panels(stack: stack, render: () {});

      final a = Panel(title: 'a', lines: const [], dismissable: false);
      final b = Panel(title: 'b', lines: const [], dismissable: false);
      panels.push(a);
      panels.push(b);

      expect(stack, [a, b]);

      panels.remove(b);
      expect(stack, [a]);
    });
  });
}
