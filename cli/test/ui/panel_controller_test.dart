import 'package:glue/src/catalog/model_catalog.dart';
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/panel_controller.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:test/test.dart';

import '../_helpers/test_config.dart';

void main() {
  group('buildHelpLines', () {
    test('help lines key column scales with width', () {
      final wide = buildHelpLines(const [], 120);
      final narrow = buildHelpLines(const [], 36);

      // The key column in a keybinding line shows up as "Ctrl+C" then padding.
      // At contentWidth=120 → keyCol = min(18, 40) = 18.
      // At contentWidth=36  → keyCol = max(10, 12) = 12.
      // Verify by measuring the distance from the padding start to the
      // description start in a known keybinding line.

      String pickLine(List<String> ls, String keyName) =>
          ls.firstWhere((l) => stripAnsi(l).contains(keyName));

      final wideLine = stripAnsi(pickLine(wide, 'Ctrl+U'));
      final narrowLine = stripAnsi(pickLine(narrow, 'Ctrl+U'));

      // Strip 2-char indent.
      final wideRight = wideLine.substring(2);
      final narrowRight = narrowLine.substring(2);

      // Find the description offset: it's the first non-space char after the
      // key text.
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

  group('PanelController history action flow', () {
    test('closing history action modal preserves unrelated stacked panels',
        () async {
      final panelStack = <PanelOverlay>[];
      var renderCount = 0;
      final controller = PanelController(
        panelStack: panelStack,
        render: () => renderCount++,
      );

      final sentinel = PanelModal(
        title: 'Sentinel',
        lines: const ['keep me'],
        dismissable: false,
      );
      panelStack.add(sentinel);

      controller.openHistory(
        entries: const [
          HistoryPanelEntry(userMessageIndex: 0, text: 'first user message'),
        ],
        onFork: (_, __) {},
        addSystemMessage: (_) {},
      );
      expect(panelStack.length, 2);
      expect(panelStack[0], same(sentinel));
      expect(panelStack[1], isA<SelectPanel<HistoryPanelEntry>>());

      final historyPanel = panelStack.last as SelectPanel<HistoryPanelEntry>;
      historyPanel.handleEvent(KeyEvent(Key.enter));
      await Future<void>.delayed(Duration.zero);
      expect(panelStack.length, 3);
      expect(panelStack.last, isA<PanelModal>());

      final actionPanel = panelStack.last as PanelModal;
      actionPanel.handleEvent(KeyEvent(Key.escape));
      await Future<void>.delayed(Duration.zero);

      expect(panelStack.length, 1);
      expect(panelStack.single, same(sentinel));
      expect(renderCount, greaterThan(0));
    });

    test('fork action emits selected history entry and closes only flow panels',
        () async {
      final panelStack = <PanelOverlay>[];
      final controller = PanelController(
        panelStack: panelStack,
        render: () {},
      );

      final sentinel = PanelModal(
        title: 'Sentinel',
        lines: const ['keep me'],
        dismissable: false,
      );
      panelStack.add(sentinel);

      int? forkIndex;
      String? forkText;
      controller.openHistory(
        entries: const [
          HistoryPanelEntry(userMessageIndex: 3, text: 'target message'),
        ],
        onFork: (index, text) {
          forkIndex = index;
          forkText = text;
        },
        addSystemMessage: (_) {},
      );

      final historyPanel = panelStack.last as SelectPanel<HistoryPanelEntry>;
      historyPanel.handleEvent(KeyEvent(Key.enter));
      await Future<void>.delayed(Duration.zero);

      final actionPanel = panelStack.last as PanelModal;
      actionPanel.handleEvent(KeyEvent(Key.enter));
      await Future<void>.delayed(Duration.zero);

      expect(forkIndex, 3);
      expect(forkText, 'target message');
      expect(panelStack.length, 1);
      expect(panelStack.single, same(sentinel));
    });
  });

  group('PanelController provider pickers', () {
    const catalog = ModelCatalog(
      version: 1,
      updatedAt: '2026-04-19',
      defaults: DefaultsConfig(model: 'anthropic/claude-sonnet-4.6'),
      capabilities: {},
      providers: {
        'anthropic': ProviderDef(
          id: 'anthropic',
          name: 'Anthropic',
          adapter: 'anthropic',
          auth: AuthSpec(kind: AuthKind.apiKey, envVar: 'ANTHROPIC_API_KEY'),
          models: {
            'claude-sonnet-4.6': ModelDef(
              id: 'claude-sonnet-4.6',
              name: 'Claude Sonnet',
            ),
          },
        ),
        'ollama': ProviderDef(
          id: 'ollama',
          name: 'Ollama',
          adapter: 'openai',
          auth: AuthSpec(kind: AuthKind.none),
          models: {'llama3.2': ModelDef(id: 'llama3.2', name: 'Llama 3.2')},
        ),
      },
    );

    test('openProviderPanel uses a responsive table header and rows', () async {
      final panelStack = <PanelOverlay>[];
      final controller = PanelController(
        panelStack: panelStack,
        render: () {},
      );

      await controller.openProviderPanel(
        config: testConfig(catalog: catalog),
        addSystemMessage: (_) {},
      );

      expect(panelStack, hasLength(1));
      final panel = panelStack.single;
      expect(panel, isA<SelectPanel<ProviderDef>>());

      // A migrated picker renders the column header above the rows.
      final grid = panel.render(80, 20, const []);
      final joined = grid.map(stripAnsi).join('\n');
      expect(joined, contains('PROVIDER'));
      expect(joined, contains('STATUS'));
      expect(joined, contains('Anthropic'));
      expect(joined, contains('Ollama'));

      panel.cancel();
      await Future<void>.delayed(Duration.zero);
    });

    test('openProviderPanel panel reflows rows on width change', () async {
      final panelStack = <PanelOverlay>[];
      final controller = PanelController(
        panelStack: panelStack,
        render: () {},
      );

      await controller.openProviderPanel(
        config: testConfig(catalog: catalog),
        addSystemMessage: (_) {},
      );

      final panel = panelStack.single;
      final wide = panel.render(120, 20, const []).map(stripAnsi).join('\n');
      final narrow = panel.render(50, 20, const []).map(stripAnsi).join('\n');
      expect(wide, isNot(equals(narrow)));

      panel.cancel();
      await Future<void>.delayed(Duration.zero);
    });
  });
}
