import 'package:test/test.dart';

import 'package:glue/src/ui/panel_controller.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/terminal/terminal.dart';

void main() {
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
}
