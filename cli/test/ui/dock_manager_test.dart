import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/components/dock.dart';
import 'package:test/test.dart';

class _StubDockedPanel extends DockedPanel {
  @override
  DockEdge edge;

  @override
  DockMode mode;

  @override
  final int extent;

  bool _visible;
  final bool _focus;
  final bool _handleResult;
  int handledCount = 0;

  _StubDockedPanel({
    required this.edge,
    required this.mode,
    required this.extent,
    bool visible = true,
    bool hasFocus = true,
    bool handleResult = true,
  })  : _visible = visible,
        _focus = hasFocus,
        _handleResult = handleResult;

  @override
  bool get visible => _visible;

  @override
  bool get hasFocus => _focus;

  @override
  void show() {
    _visible = true;
  }

  @override
  void dismiss() {
    _visible = false;
  }

  @override
  bool handleEvent(TerminalEvent event) {
    handledCount++;
    return _handleResult;
  }

  @override
  List<String> render(int width, int height) =>
      List.generate(height, (_) => 'x' * width);
}

void main() {
  group('DockManager.resolveInsets', () {
    test('uses max pinned extent per edge and ignores floating panels', () {
      final manager = DockManager();
      manager.add(_StubDockedPanel(
        edge: DockEdge.left,
        mode: DockMode.pinned,
        extent: 16,
      ));
      manager.add(_StubDockedPanel(
        edge: DockEdge.left,
        mode: DockMode.pinned,
        extent: 8,
      ));
      manager.add(_StubDockedPanel(
        edge: DockEdge.right,
        mode: DockMode.floating,
        extent: 20,
      ));
      manager.add(_StubDockedPanel(
        edge: DockEdge.top,
        mode: DockMode.pinned,
        extent: 3,
      ));

      final insets =
          manager.resolveInsets(terminalColumns: 120, terminalRows: 40);
      expect(insets.left, 16);
      expect(insets.top, 3);
      expect(insets.right, 0);
      expect(insets.bottom, 0);
    });

    test('normalizes oversized left/right insets to keep one output column',
        () {
      final manager = DockManager();
      manager.add(_StubDockedPanel(
        edge: DockEdge.left,
        mode: DockMode.pinned,
        extent: 200,
      ));
      manager.add(_StubDockedPanel(
        edge: DockEdge.right,
        mode: DockMode.pinned,
        extent: 200,
      ));

      final insets =
          manager.resolveInsets(terminalColumns: 80, terminalRows: 24);
      expect(insets.left + insets.right, 79);
    });
  });

  group('DockManager.handleEvent', () {
    test('routes to last focused visible panel first', () {
      final manager = DockManager();
      final first = _StubDockedPanel(
        edge: DockEdge.left,
        mode: DockMode.floating,
        extent: 20,
        handleResult: false,
      );
      final second = _StubDockedPanel(
        edge: DockEdge.right,
        mode: DockMode.floating,
        extent: 20,
        handleResult: true,
      );
      manager.add(first);
      manager.add(second);

      final handled = manager.handleEvent(KeyEvent(Key.enter));
      expect(handled, isTrue);
      expect(first.handledCount, 0);
      expect(second.handledCount, 1);
    });
  });

  group('DockManager.buildRenderPlans', () {
    test('creates pinned and floating panel rectangles from viewport', () {
      final manager = DockManager();
      manager.add(_StubDockedPanel(
        edge: DockEdge.left,
        mode: DockMode.pinned,
        extent: 10,
      ));
      manager.add(_StubDockedPanel(
        edge: DockEdge.right,
        mode: DockMode.floating,
        extent: 30,
      ));

      final plans = manager.buildRenderPlans(
        viewport: const DockViewport(
          outputTop: 3,
          outputBottom: 20,
          outputLeft: 11,
          outputRight: 100,
          overlayTop: 23,
        ),
        terminalColumns: 120,
      );

      expect(plans, hasLength(2));
      expect(plans[0].rect.row, 3);
      expect(plans[0].rect.col, 1);
      expect(plans[0].rect.width, 10);
      expect(plans[0].rect.height, 18);

      expect(plans[1].rect.row, 3);
      expect(plans[1].rect.col, 71);
      expect(plans[1].rect.width, 30);
      expect(plans[1].rect.height, 18);
    });

    test('places pinned bottom panel in reserved bottom dock zone', () {
      final manager = DockManager();
      manager.add(_StubDockedPanel(
        edge: DockEdge.bottom,
        mode: DockMode.pinned,
        extent: 2,
      ));

      final plans = manager.buildRenderPlans(
        viewport: const DockViewport(
          outputTop: 2,
          outputBottom: 18,
          outputLeft: 1,
          outputRight: 80,
          overlayTop: 22,
        ),
        terminalColumns: 80,
      );

      expect(plans, hasLength(1));
      expect(plans.first.rect.row, 20);
      expect(plans.first.rect.height, 2);
      expect(plans.first.rect.width, 80);
    });
  });
}
