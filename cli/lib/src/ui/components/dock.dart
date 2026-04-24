import 'dart:math';

import 'package:glue/src/terminal/terminal.dart';

enum DockEdge { left, top, right, bottom }

enum DockMode { floating, pinned }

abstract class DockedPanel {
  DockEdge get edge;
  set edge(DockEdge value);

  DockMode get mode;
  set mode(DockMode value);

  /// Size along the docking axis:
  /// - columns for left/right
  /// - rows for top/bottom
  int get extent;

  bool get visible;
  bool get hasFocus;

  bool handleEvent(TerminalEvent event);

  /// Render panel content into [width] x [height].
  List<String> render(int width, int height);

  void show();
  void dismiss();
}

class DockInsets {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const DockInsets({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });
}

class DockViewport {
  final int outputTop;
  final int outputBottom;
  final int outputLeft;
  final int outputRight;
  final int overlayTop;

  const DockViewport({
    required this.outputTop,
    required this.outputBottom,
    required this.outputLeft,
    required this.outputRight,
    required this.overlayTop,
  });

  int get outputWidth => max(0, outputRight - outputLeft + 1);
  int get outputHeight => max(0, outputBottom - outputTop + 1);
}

class DockRect {
  final int row;
  final int col;
  final int width;
  final int height;

  const DockRect({
    required this.row,
    required this.col,
    required this.width,
    required this.height,
  });
}

class DockRenderPlan {
  final DockedPanel panel;
  final DockRect rect;
  final List<String> lines;

  const DockRenderPlan({
    required this.panel,
    required this.rect,
    required this.lines,
  });
}

class DockManager {
  static const _maxHorizontalFloatingHeight = 38;

  final List<DockedPanel> _panels = [];

  List<DockedPanel> get panels => List.unmodifiable(_panels);

  List<DockedPanel> get visiblePanels =>
      _panels.where((panel) => panel.visible).toList(growable: false);

  bool get hasVisibleFloatingPanels =>
      visiblePanels.any((panel) => panel.mode == DockMode.floating);

  void add(DockedPanel panel) {
    if (_panels.contains(panel)) return;
    _panels.add(panel);
  }

  void remove(DockedPanel panel) {
    _panels.remove(panel);
  }

  DockInsets resolveInsets({
    required int terminalColumns,
    required int terminalRows,
  }) {
    final leftRaw = _maxPinnedExtent(DockEdge.left).clamp(0, terminalColumns);
    final rightRaw = _maxPinnedExtent(DockEdge.right).clamp(0, terminalColumns);
    final topRaw = _maxPinnedExtent(DockEdge.top).clamp(0, terminalRows);
    final bottomRaw = _maxPinnedExtent(DockEdge.bottom).clamp(0, terminalRows);

    final horizontal = _normalizePair(
      leftRaw,
      rightRaw,
      max(0, terminalColumns - 1),
    );
    final vertical = _normalizePair(
      topRaw,
      bottomRaw,
      max(0, terminalRows - 3),
    );

    return DockInsets(
      left: horizontal.$1,
      right: horizontal.$2,
      top: vertical.$1,
      bottom: vertical.$2,
    );
  }

  List<DockRenderPlan> buildRenderPlans({
    required DockViewport viewport,
    required int terminalColumns,
  }) {
    final plans = <DockRenderPlan>[];
    for (final panel in visiblePanels) {
      final rect = switch (panel.mode) {
        DockMode.pinned => _pinnedRect(
            panel: panel,
            viewport: viewport,
            terminalColumns: terminalColumns,
          ),
        DockMode.floating => _floatingRect(
            panel: panel,
            viewport: viewport,
          ),
      };
      if (rect == null || rect.width <= 0 || rect.height <= 0) continue;

      plans.add(DockRenderPlan(
        panel: panel,
        rect: rect,
        lines: panel.render(rect.width, rect.height),
      ));
    }
    return plans;
  }

  bool handleEvent(TerminalEvent event) {
    for (final panel in _panels.reversed) {
      if (!panel.visible || !panel.hasFocus) continue;
      if (panel.handleEvent(event)) return true;
    }
    return false;
  }

  int _maxPinnedExtent(DockEdge edge) {
    var maxExtent = 0;
    for (final panel in _panels) {
      if (!panel.visible || panel.mode != DockMode.pinned) continue;
      if (panel.edge != edge) continue;
      maxExtent = max(maxExtent, panel.extent);
    }
    return maxExtent;
  }

  (int, int) _normalizePair(int first, int second, int maxTotal) {
    if (maxTotal <= 0) return (0, 0);
    if (first + second <= maxTotal) return (first, second);
    if (first == 0 && second == 0) return (0, 0);

    final ratioFirst = first / (first + second);
    final normalizedFirst = (maxTotal * ratioFirst).floor();
    final normalizedSecond = maxTotal - normalizedFirst;
    return (normalizedFirst, normalizedSecond);
  }

  DockRect? _pinnedRect({
    required DockedPanel panel,
    required DockViewport viewport,
    required int terminalColumns,
  }) {
    switch (panel.edge) {
      case DockEdge.left:
        final available = max(0, viewport.outputLeft - 1);
        final width = min(panel.extent, available);
        if (width <= 0) return null;
        return DockRect(
          row: viewport.outputTop,
          col: 1,
          width: width,
          height: viewport.outputHeight,
        );
      case DockEdge.right:
        final available = max(0, terminalColumns - viewport.outputRight);
        final width = min(panel.extent, available);
        if (width <= 0) return null;
        return DockRect(
          row: viewport.outputTop,
          col: terminalColumns - width + 1,
          width: width,
          height: viewport.outputHeight,
        );
      case DockEdge.top:
        final available = max(0, viewport.outputTop - 1);
        final height = min(panel.extent, available);
        if (height <= 0) return null;
        return DockRect(
          row: 1,
          col: viewport.outputLeft,
          width: viewport.outputWidth,
          height: height,
        );
      case DockEdge.bottom:
        final available =
            max(0, viewport.overlayTop - viewport.outputBottom - 1);
        final height = min(panel.extent, available);
        if (height <= 0) return null;
        return DockRect(
          row: viewport.overlayTop - height,
          col: viewport.outputLeft,
          width: viewport.outputWidth,
          height: height,
        );
    }
  }

  DockRect? _floatingRect({
    required DockedPanel panel,
    required DockViewport viewport,
  }) {
    if (viewport.outputWidth <= 0 || viewport.outputHeight <= 0) return null;

    switch (panel.edge) {
      case DockEdge.left:
      case DockEdge.right:
        final width =
            panel.extent.clamp(1, max(1, viewport.outputWidth ~/ 2)).toInt();
        final col = panel.edge == DockEdge.left
            ? viewport.outputLeft
            : viewport.outputRight - width + 1;
        return DockRect(
          row: viewport.outputTop,
          col: col,
          width: width,
          height: viewport.outputHeight,
        );
      case DockEdge.top:
      case DockEdge.bottom:
        final maxHeight =
            min(viewport.outputHeight, _maxHorizontalFloatingHeight);
        final height = panel.extent.clamp(1, max(1, maxHeight)).toInt();
        final row = panel.edge == DockEdge.top
            ? viewport.outputTop
            : viewport.outputBottom - height + 1;
        return DockRect(
          row: row,
          col: viewport.outputLeft,
          width: viewport.outputWidth,
          height: height,
        );
    }
  }
}
